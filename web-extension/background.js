/*
 * VisioNext — extension background for the global mute bridge.
 *
 * Keeps the list of calls in this browser (reported by call-bridge.js) and, while
 * there is at least one, a native-messaging port to the VisioNext app. Relays the
 * app's `setMuted` to the call tabs. Visio is always on; Google Meet and Teams are
 * opt-in from the popup (optional host permissions): this file registers their
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
/** Sites the user opts into from the popup. Keep origins in sync with popup.js. */
const OPTIONAL = [
  { id: 'meet', origins: ['https://meet.google.com/*'], js: ['providers/meet.js', 'call-bridge.js'] },
  {
    id: 'teams',
    origins: ['https://teams.microsoft.com/*', 'https://teams.cloud.microsoft/*', 'https://teams.live.com/*'],
    js: ['providers/teams.js', 'call-bridge.js'],
  },
];

const sessions = new Map(); // tabId -> { muted, canUnmute }; only drives the port lifecycle
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
  const tabs = await api.tabs.query({ url: site.origins });
  for (const tab of tabs) {
    Promise.resolve(api.scripting.executeScript({ target: { tabId: tab.id }, files: site.js })).catch(() => {});
  }
}

/** Register the content scripts of opted-in sites, unregister the others. */
async function syncSites() {
  if (!api.scripting || !api.scripting.registerContentScripts) return;
  for (const site of OPTIONAL) {
    const id = 'vn-' + site.id;
    try {
      const registered = (await api.scripting.getRegisteredContentScripts({ ids: [id] })).length > 0;
      const on = await allowed(site);
      if (on && !registered) {
        await api.scripting.registerContentScripts([{
          id, matches: site.origins, js: site.js, runAt: 'document_idle', persistAcrossSessions: true,
        }]);
        await inject(site); // tabs opened before the permission was granted
      } else if (!on && registered) {
        await api.scripting.unregisterContentScripts({ ids: [id] });
      }
    } catch (e) { /* this browser can't register scripts: the site stays off */ }
  }
}

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
    const tabs = await api.tabs.query({ url: origins });
    for (const tab of tabs) tell(tab.id, msg.value);
  } catch (e) { /* tab gone or query failed */ }
}

function ensurePort() {
  if (port) return port;
  try {
    port = api.runtime.connectNative(HOST);
  } catch (e) {
    return null;
  }
  port.onMessage.addListener(onAppMessage);
  port.onDisconnect.addListener(() => {
    void api.runtime.lastError; // app not running: Chrome reports it here
    port = null;
  });
  return port;
}

function post(msg) {
  const p = ensurePort();
  if (!p) return;
  try {
    p.postMessage(msg);
  } catch (e) {
    port = null; // disconnected under us; the next report reconnects
  }
}

function report(tabId, msg) {
  if (msg.type === 'bye') sessions.delete(tabId);
  else sessions.set(tabId, { muted: msg.muted, canUnmute: msg.canUnmute });

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

// Guarded: a missing event in one browser (Safari…) mustn't take the whole background down.
api.runtime.onStartup?.addListener(syncSites);
api.permissions?.onAdded?.addListener(syncSites);
api.permissions?.onRemoved?.addListener(syncSites);

api.runtime.onInstalled.addListener(async () => {
  await syncSites();
  // An update orphans the call bridges already running in open call tabs (they stop
  // themselves): start fresh ones so calls in progress stay muteable.
  for (const site of await activeSites()) await inject(site);
});
