/*
 * VisioNext — extension background for the global mute bridge.
 *
 * Keeps the list of Visio calls in this browser (reported by call-bridge.js) and,
 * while there is at least one, a native-messaging port to the VisioNext app. Relays
 * the app's `setMuted` to every call tab.
 *
 * Chrome/Firefox: the port reaches the app through the `com.meidosem.visionext`
 * native host (a pipe to the app's socket). Safari: it reaches the containing app's
 * extension handler, and the app answers via SFSafariApplication.dispatchMessage,
 * which arrives here wrapped as { name, userInfo }.
 */
'use strict';

const api = globalThis.browser ?? globalThis.chrome;
const HOST = 'com.meidosem.visionext';
const sessions = new Map(); // tabId -> { muted, canUnmute }
let port = null;

function onAppMessage(raw) {
  const msg = (raw && raw.userInfo) || raw;
  if (!msg || msg.type !== 'setMuted') return;
  // An unmute names its one tab (the app only unmutes when it knows exactly which
  // call); a mute goes to every call.
  const targets = msg.tabId != null ? [msg.tabId] : [...sessions.keys()];
  for (const tabId of targets) {
    if (!sessions.has(tabId)) continue;
    Promise.resolve(api.tabs.sendMessage(tabId, { type: 'setMuted', value: msg.value })).catch(() => {});
  }
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
