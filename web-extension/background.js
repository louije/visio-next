/*
 * VisioNext — extension background for the global mute bridge.
 *
 * Keeps the list of calls in this browser (reported by call-bridge.js) and, while
 * there is at least one, a native-messaging port to the VisioNext app. Relays the
 * app's `setMuted` to the call tabs, and has sites.js keep the opted-in sites' content
 * scripts registered (Google Meet and Teams, from the options page).
 *
 * Chrome/Firefox: the port reaches the app through the `com.meidosem.visionext`
 * native host (a pipe to the app's socket). Safari: it reaches the containing app's
 * extension handler, and the app answers via SFSafariApplication.dispatchMessage,
 * which arrives here wrapped as { name, userInfo }.
 */
'use strict';

// The sites and their registration (sites.js): a service worker loads it here, Firefox
// from the manifest's background.scripts.
if (typeof importScripts === 'function' && !globalThis.VNSites) importScripts('sites.js');

const api = globalThis.browser ?? globalThis.chrome;
const HOST = 'com.meidosem.visionext';

const { VISIO, activeSites, tabIdsFor, inject, sync, resync, stopRevoked } = globalThis.VNSites;

const sessions = new Set(); // tab ids with a call; only drives the port lifecycle
let port = null;

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
    // Also known sessions: tabs a url query may miss (Safari; a call on a site being
    // revoked, until its bridge has stopped) still get muted.
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

// Guarded: a missing event in one browser (Safari…) mustn't take the whole background down.
api.runtime.onStartup?.addListener(sync);
api.permissions?.onAdded?.addListener(sync);
api.permissions?.onRemoved?.addListener((removed) => {
  sync();
  stopRevoked(removed && removed.origins);
});

api.runtime.onInstalled.addListener(async (details) => {
  // Only when this extension is installed or updated (not on a browser update, which
  // would leave restoring tabs briefly without a registration): re-register from scratch.
  const fresh = details.reason === 'install' || details.reason === 'update';
  await (fresh ? resync() : sync());
  // An update orphans the call bridges already running in open call tabs (they stop
  // themselves): start fresh ones so calls in progress stay muteable. Visio only: the
  // resync re-registered the opted-in sites, which injects their open tabs.
  if (fresh) await inject(VISIO).catch(() => {});
});

sync(); // once per worker start
