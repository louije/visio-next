/*
 * VisioNext — call bridge content script.
 *
 * Reports this tab's call (Visio, Google Meet, Teams) to the extension background,
 * which relays it to the VisioNext app, and mutes/unmutes on command.
 *
 * What a call looks like on each site lives in providers/*.js, loaded before this file
 * (each registers on `globalThis.__vnProviders`: `read(doc)` → null when not in a call,
 * else { muted: true|false|null, canUnmute }; `toggle(doc)`). This file is the
 * site-independent part: watch the page, report changes and a heartbeat, press, and
 * check a second later that the press took.
 */
(function () {
  'use strict';

  var VERIFY_MS = 1000;

  /**
   * 'press' when a toggle is needed to reach `wantMuted`, else 'skip'. `pending` is
   * null or { muted, at } for a press the page has not reflected yet: repeating it
   * within VERIFY_MS would toggle back.
   */
  function planMute(state, wantMuted, pending, now) {
    if (!state || state.muted === null) return 'skip';
    if (pending && pending.muted === wantMuted && now - pending.at < VERIFY_MS) return 'skip';
    if (state.muted === wantMuted) return 'skip';
    if (!wantMuted && !state.canUnmute) return 'skip';
    return 'press';
  }

  /** Whether two reads look the same to the app. */
  function sameState(a, b) {
    return !!a && !!b && a.muted === b.muted && a.canUnmute === b.canUnmute;
  }

  function pickProvider(list, host) {
    for (var k = 0; k < list.length; k++) if (list[k].matches(host)) return list[k];
    return null;
  }

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { planMute: planMute, sameState: sameState, pickProvider: pickProvider, VERIFY_MS: VERIFY_MS };
  }

  // ---- DOM + messaging (extension only) ------------------------------------
  if (typeof document === 'undefined') return;
  // Registered scripts and executeScript (after an update or a new permission) can
  // both land in the same page; run once.
  if (globalThis.__vnCallBridge) return;
  globalThis.__vnCallBridge = true;

  var api = (typeof browser !== 'undefined') ? browser
    : (typeof chrome !== 'undefined') ? chrome : null;
  var provider = pickProvider(globalThis.__vnProviders || [], location.host);
  if (!api || !api.runtime || !provider) return;

  var HEARTBEAT_MS = 30000;
  var THROTTLE_MS = 250;
  // Pages swap their controls around (Meet replaces them); only a lasting absence
  // ends the call.
  var BYE_GRACE_MS = 2000;
  var WATCHED = [
    'data-microphone-enabled', 'data-can-publish-microphone', // Visio
    'data-is-muted', // Meet
    'data-state', 'data-track-action-scenario', // Teams
    'aria-label', 'aria-pressed', 'disabled', 'aria-disabled',
  ];

  var last = null;      // last reported { muted, canUnmute }; null = not in a call
  var pending = null;   // { muted, at } for a press not reflected yet
  var toggleOff = false; // a click that didn't take: stop clicking on this page
  var dead = false;
  var heartbeat = null;
  var byeTimer = null;
  var refreshTimer = null;
  var docMo = null;

  // Extension reloaded: this page's script is orphaned. Stop everything.
  function teardown() {
    dead = true;
    if (docMo) docMo.disconnect();
    clearInterval(heartbeat);
    clearTimeout(byeTimer);
    clearTimeout(refreshTimer);
    last = null; pending = null;
  }

  function send(msg) {
    if (dead) return;
    if (!api.runtime || !api.runtime.id) { teardown(); return; }
    try {
      var p = api.runtime.sendMessage(msg);
      if (p && p.catch) p.catch(function () {});
    } catch (e) { teardown(); }
  }

  function sendState() {
    if (last) send({ type: 'state', muted: last.muted, canUnmute: last.canUnmute });
  }

  function leaveCall() {
    clearTimeout(byeTimer); byeTimer = null;
    if (!last) return;
    clearInterval(heartbeat); heartbeat = null;
    last = null; pending = null;
    send({ type: 'bye' });
  }

  function refresh() {
    refreshTimer = null;
    if (dead) return;
    var s = provider.read(document);
    if (!s) {
      if (last && !byeTimer) byeTimer = setTimeout(leaveCall, BYE_GRACE_MS);
      return;
    }
    clearTimeout(byeTimer); byeTimer = null;
    if (s.muted === null) return; // in a call, momentarily unreadable: wait
    if (pending && pending.muted === s.muted) pending = null;
    if (!last) heartbeat = setInterval(sendState, HEARTBEAT_MS);
    if (sameState(s, last)) return;
    last = s;
    sendState();
  }

  function schedule() {
    if (!refreshTimer && !dead) refreshTimer = setTimeout(refresh, THROTTLE_MS);
  }

  // A second after a press: did it take? Report the real state either way.
  function verify() {
    refresh();
    if (pending && Date.now() - pending.at >= VERIFY_MS) {
      // For click-based providers a press that didn't take may mean we clicked the
      // wrong control: never keep doing that on this page.
      if (provider.guardToggle) toggleOff = true;
      pending = null;
    }
    sendState();
  }

  api.runtime.onMessage.addListener(function (msg) {
    if (!msg || msg.type !== 'setMuted' || dead || toggleOff) return;
    var want = !!msg.value;
    if (planMute(provider.read(document), want, pending, Date.now()) !== 'press') return;
    if (!provider.toggle(document)) return;
    pending = { muted: want, at: Date.now() };
    setTimeout(verify, VERIFY_MS);
  });

  docMo = new MutationObserver(schedule);
  docMo.observe(document.documentElement, {
    childList: true, subtree: true, attributes: true, attributeFilter: WATCHED,
  });
  window.addEventListener('pagehide', leaveCall);
  window.addEventListener('pageshow', schedule);
  schedule();
})();
