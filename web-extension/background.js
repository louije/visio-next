/*
 * VisioNext — extension background for the global mute bridge.
 *
 * Keeps the list of calls in this browser (reported by call-bridge.js) and, while
 * there is at least one, a native-messaging port to the VisioNext app. Relays the
 * app's `setMuted` to the call tabs. Visio is always on; Google Meet and Teams are
 * opt-in from the options page (optional host permissions): this file registers their
 * content scripts when allowed and unregisters them when not.
 *
 * Chrome/Firefox: the port reaches the app through the `com.meidosem.visionext`
 * native host (a pipe to the app's socket). Safari: it reaches the containing app's
 * extension handler, and the app answers via SFSafariApplication.dispatchMessage,
 * which arrives here wrapped as { name, userInfo }.
 */
'use strict';

const api = globalThis.browser ?? globalThis.chrome;
const HOST = 'com.meidosem.visionext';

const VISIO = { origins: ['https://visio.numerique.gouv.fr/*'], js: ['providers/visio.js', 'call-bridge.js'] };
/**
 * Sites the user opts into from the options page. Their origins together must equal the
 * manifest's optional_host_permissions, from which options.js builds its switches
 * (checked by sites.test.cjs, with VISIO against the static content script).
 */
const OPTIONAL = [
  { id: 'meet', origins: ['https://meet.google.com/*'], js: ['providers/meet.js', 'call-bridge.js'] },
  {
    id: 'teams',
    origins: ['https://teams.microsoft.com/*', 'https://teams.cloud.microsoft/*', 'https://teams.live.com/*'],
    js: ['providers/teams.js', 'call-bridge.js'],
  },
];

const sessions = new Set(); // tab ids with a call; only drives the port lifecycle
let port = null;

async function allowed(site) {
  try {
    return await api.permissions.contains({ origins: site.origins });
  } catch (e) {
    return false;
  }
}

/** Visio plus every opted-in site. */
async function activeSites() {
  const sites = [VISIO];
  for (const site of OPTIONAL) if (await allowed(site)) sites.push(site);
  return sites;
}

/** Start the call bridge in a site's open tabs (call-bridge.js runs once per page). */
async function inject(site) {
  if (!api.scripting) return;
  try {
    for (const id of await tabIdsFor(site.origins)) {
      Promise.resolve(api.scripting.executeScript({ target: { tabId: id }, files: site.js })).catch(() => {});
    }
  } catch (e) { /* query failed */ }
}

/** Ids of the tabs open on any of these origins (one query per origin: robust across browsers). */
async function tabIdsFor(origins) {
  const ids = new Set();
  for (const origin of origins) {
    try {
      for (const tab of await api.tabs.query({ url: origin })) ids.add(tab.id);
    } catch (e) { /* bad pattern for this browser: skip it */ }
  }
  return ids;
}

/** Register the content scripts of opted-in sites, unregister the others. */
async function doSyncSites() {
  if (!api.scripting || !api.scripting.registerContentScripts) return;
  for (const site of OPTIONAL) {
    const id = 'vn-' + site.id;
    try {
      const registered = (await api.scripting.getRegisteredContentScripts()).some((s) => s.id === id);
      const on = await allowed(site);
      if (on && !registered) {
        await api.scripting.registerContentScripts([{
          id, matches: site.origins, js: site.js, runAt: 'document_idle', persistAcrossSessions: true,
        }]);
        await inject(site).catch(() => {}); // tabs opened before the permission was granted
      } else if (!on && registered) {
        await api.scripting.unregisterContentScripts({ ids: [id] });
      }
    } catch (e) { /* this browser can't register scripts: the site stays off */ }
  }
}

let syncing = Promise.resolve();
/** Serialized: overlapping permission events / startups must not interleave. */
function syncSites() { return (syncing = syncing.then(doSyncSites, doSyncSites)); }

function tell(tabId, value) {
  Promise.resolve(api.tabs.sendMessage(tabId, { type: 'setMuted', value })).catch(() => {});
}

async function onAppMessage(raw) {
  const msg = (raw && raw.userInfo) || raw;
  if (!msg || msg.type !== 'setMuted') return;
  // An unmute names its one tab (the app only unmutes when it knows exactly which
  // call). A mute goes to every call site's tab, not just the registry: the background
  // may have been unloaded and restarted since the last heartbeat. Tabs not in a call
  // ignore it (call-bridge.js).
  try {
    if (msg.tabId != null) return tell(msg.tabId, msg.value);
    const origins = (await activeSites()).flatMap((site) => site.origins);
    // Also known sessions: a call on a site revoked mid-call is still muted.
    const ids = new Set([...(await tabIdsFor(origins)), ...sessions]);
    for (const id of ids) tell(id, msg.value);
  } catch (e) { /* tab gone or query failed */ }
}

function ensurePort() {
  if (port) return port;
  let p;
  try {
    p = api.runtime.connectNative(HOST);
  } catch (e) {
    return null;
  }
  port = p;
  p.onMessage.addListener(onAppMessage);
  p.onDisconnect.addListener(() => {
    void api.runtime.lastError; // app not running: Chrome reports it here
    // A late event from a port already replaced must not drop the new one.
    if (port === p) port = null;
  });
  return p;
}

function post(msg) {
  const p = ensurePort();
  if (!p) return;
  try {
    p.postMessage(msg);
  } catch (e) {
    if (port === p) port = null; // disconnected under us; the next report reconnects
  }
}

function report(tabId, msg) {
  // A bye for a call the app never heard of (tab closed after the worker restarted…):
  // nothing to tell, and connecting would launch the native host for nothing.
  if (msg.type === 'bye' && !sessions.has(tabId) && !port) return;
  if (msg.type === 'bye') sessions.delete(tabId);
  else sessions.add(tabId);

  post({ ...msg, tabId });

  if (sessions.size === 0 && port) {
    port.disconnect();
    port = null;
  }
}

api.runtime.onMessage.addListener((msg, sender) => {
  if (!sender.tab || !msg || (msg.type !== 'state' && msg.type !== 'bye')) return;
  report(sender.tab.id, msg);
});

api.tabs.onRemoved.addListener((tabId) => {
  if (sessions.has(tabId)) report(tabId, { type: 'bye' });
});

/**
 * Stop the call bridges already running on origins the user just revoked: unregistering
 * only spares new pages. Every tab gets it (each bridge checks its own URL): once access
 * is gone, a `url` query no longer sees those tabs.
 */
async function stopOn(origins) {
  if (!origins || !origins.length) return;
  try {
    for (const tab of await api.tabs.query({})) {
      Promise.resolve(api.tabs.sendMessage(tab.id, { type: 'stop', origins })).catch(() => {});
    }
  } catch (e) { /* query failed */ }
}

// Guarded: a missing event in one browser (Safari…) mustn't take the whole background down.
api.runtime.onStartup?.addListener(syncSites);
api.permissions?.onAdded?.addListener(syncSites);
api.permissions?.onRemoved?.addListener((removed) => {
  syncSites();
  stopOn(removed && removed.origins);
});

/** Drop our registrations so the next sync registers this version's js/matches. */
async function dropRegistrations() {
  try {
    if (api.scripting && api.scripting.getRegisteredContentScripts) {
      const ids = (await api.scripting.getRegisteredContentScripts()).map((s) => s.id).filter((id) => id.startsWith('vn-'));
      if (ids.length) await api.scripting.unregisterContentScripts({ ids });
    }
  } catch (e) { /* nothing to clean */ }
}

api.runtime.onInstalled.addListener(async (details) => {
  // Only when this extension is installed or updated (not on a browser update, which
  // would leave restoring tabs briefly without a registration). Through the sync chain,
  // so it can't interleave with a sync already running.
  if (details.reason === 'install' || details.reason === 'update') {
    syncing = syncing.then(dropRegistrations, dropRegistrations);
  }
  await syncSites();
  // An update orphans the call bridges already running in open call tabs (they stop
  // themselves): start fresh ones so calls in progress stay muteable. Visio only: the
  // sync above re-registered the opted-in sites, which injects their open tabs.
  await inject(VISIO).catch(() => {});
});

syncSites(); // once per worker start
