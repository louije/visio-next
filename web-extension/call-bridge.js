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
   * would toggle back, however long the page takes (the core always clears `pending`:
   * matching read, verify, second check, leaving the call).
   */
  function planMute(state, wantMuted, pending) {
    if (!state || state.muted === null) return 'skip';
    if (pending && pending.muted === wantMuted) return 'skip';
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
  // both land in the same page: a live instance wins; an orphan from the previous
  // version (same isolated world in Chrome) is stopped and replaced.
  var api = (typeof browser !== 'undefined') ? browser
    : (typeof chrome !== 'undefined') ? chrome : null;
  var provider = pickProvider(globalThis.__vnProviders || [], location.host);
  if (!api || !api.runtime || !provider) return;
  var prev = globalThis.__vnCallBridge;
  if (prev && prev.alive && prev.alive()) return;
  if (prev && prev.stop) prev.stop(); // orphan from the previous version (same isolated world)

  var HEARTBEAT_MS = 30000;
  var THROTTLE_MS = 250;
  // Pages swap their controls around (Meet replaces them); only a lasting absence
  // ends the call.
  var BYE_GRACE_MS = 2000;
  var WATCHED = [
    'data-microphone-enabled', 'data-can-publish-microphone', // Visio
    'data-is-muted', // Meet
    'data-state', 'data-track-action-scenario', // Teams
    'aria-label', 'disabled', 'aria-disabled',
  ];

  var last = null;      // last reported { muted, canUnmute }; null = not in a call
  var pending = null;   // { muted, at } for a press not reflected yet
  var toggleOff = false; // a click that didn't take: stop clicking on this page
  var dead = false;
  var heartbeat = null;
  var byeTimer = null;
  var refreshTimer = null;
  var retryTimer = null;
  var docMo = null;

  // Extension reloaded: this page's script is orphaned. Stop everything.
  function teardown() {
    dead = true;
    if (docMo) docMo.disconnect();
    clearInterval(heartbeat);
    clearTimeout(byeTimer);
    clearTimeout(refreshTimer);
    clearTimeout(retryTimer);
    last = null; pending = null;
    if (globalThis.__vnCallBridge === me) delete globalThis.__vnCallBridge;
  }

  var me = {
    alive: function () { return !dead && !!(api && api.runtime && api.runtime.id); },
    stop: teardown,
  };
  globalThis.__vnCallBridge = me;

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

  function byeCheck() {
    byeTimer = null;
    if (dead) return;
    if (provider.read(document)) schedule(); else leaveCall();
  }

  function beat() { refresh(); sendState(); }

  function refresh() {
    clearTimeout(refreshTimer);
    refreshTimer = null;
    if (dead) return;
    if (!api.runtime || !api.runtime.id) { teardown(); return; }
    var s = provider.read(document);
    if (!s) {
      if (last && !byeTimer) byeTimer = setTimeout(byeCheck, BYE_GRACE_MS);
      return;
    }
    clearTimeout(byeTimer); byeTimer = null;
    if (s.muted === null) { // in a call, momentarily unreadable: retry without a mutation
      if (last && !retryTimer) {
        retryTimer = setTimeout(function () { retryTimer = null; schedule(); }, 1000);
      }
      return;
    }
    if (pending && pending.muted === s.muted) pending = null;
    if (!last) heartbeat = setInterval(beat, HEARTBEAT_MS);
    if (sameState(s, last)) return;
    last = s;
    sendState();
  }

  function schedule() {
    if (!refreshTimer && !dead) refreshTimer = setTimeout(refresh, THROTTLE_MS);
  }

  // A second after a press: did it take? Report the real state either way.
  function verify(p) {
    refresh(); sendState();
    if (pending !== p) return; // taken, or superseded by a newer press
    var s = provider.read(document);
    if (!s || s.muted === null || s.muted === p.muted) { pending = null; return; }
    if (!provider.guardToggle) { pending = null; return; }
    setTimeout(function () { // second chance before giving up on this page
      var s2 = provider.read(document);
      if (pending === p && s2 && s2.muted !== null && s2.muted !== p.muted) {
        toggleOff = true;
        console.warn('VisioNext: a press did not take; stopped pressing on this page');
      }
      if (pending === p) pending = null;
    }, 2000);
  }

  api.runtime.onMessage.addListener(function (msg) {
    if (!msg || msg.type !== 'setMuted' || dead || toggleOff) return;
    var want = !!msg.value;
    if (planMute(provider.read(document), want, pending) !== 'press') return;
    if (!provider.toggle(document)) return;
    var p = pending = { muted: want, at: Date.now() };
    setTimeout(function () { verify(p); }, VERIFY_MS);
  });

  docMo = new MutationObserver(schedule);
  docMo.observe(document.documentElement, {
    childList: true, subtree: true, attributes: true, characterData: true, attributeFilter: WATCHED,
  });
  window.addEventListener('pagehide', leaveCall);
  window.addEventListener('pageshow', schedule);
  schedule();
})();
