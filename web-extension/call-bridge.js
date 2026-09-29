/*
 * VisioNext — call bridge content script.
 *
 * Reports this tab's Visio call to the extension background (which relays it to the
 * VisioNext app), and mutes/unmutes on command.
 *
 * State comes from Visio's own `#media-state` element (mounted only in a room, meant
 * for external tools). Muting presses Visio's Ctrl+D shortcut: its listener sits on
 * `window` and ignores focus, and an event dispatched on `window` never passes through
 * the chat textarea that swallows real keypresses.
 */
(function () {
  'use strict';

  var VERIFY_MS = 1000;

  /** null unless the attribute is exactly 'true' or 'false' (unknown: report nothing). */
  function readState(el) {
    var mic = el.dataset.microphoneEnabled;
    if (mic !== 'true' && mic !== 'false') return null;
    return {
      muted: mic !== 'true',
      canUnmute: el.dataset.canPublishMicrophone !== 'false',
    };
  }

  /**
   * 'press' when Ctrl+D must be sent to reach `wantMuted`, else 'skip'. `pending` is
   * null or { muted, at } for a press Visio has not reflected yet: repeating it within
   * VERIFY_MS would toggle back.
   */
  function planMute(state, wantMuted, pending, now) {
    if (!state) return 'skip';
    if (pending && pending.muted === wantMuted && now - pending.at < VERIFY_MS) return 'skip';
    if (state.muted === wantMuted) return 'skip';
    if (!wantMuted && !state.canUnmute) return 'skip';
    return 'press';
  }

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { readState: readState, planMute: planMute, VERIFY_MS: VERIFY_MS };
  }

  // ---- DOM + messaging (extension only) ------------------------------------
  if (typeof document === 'undefined') return;
  var api = (typeof browser !== 'undefined') ? browser
    : (typeof chrome !== 'undefined') ? chrome : null;
  if (!api || !api.runtime) return;

  var HEARTBEAT_MS = 30000;
  var el = null;
  var attrMo = null;
  var docMo = null;
  var pending = null;
  var dead = false;
  var heartbeat = null;

  // Extension reloaded: this page's script is orphaned. Stop everything.
  function teardown() {
    dead = true;
    if (attrMo) attrMo.disconnect();
    if (docMo) docMo.disconnect();
    clearInterval(heartbeat);
    el = null; attrMo = null; heartbeat = null; pending = null;
  }

  function send(msg) {
    if (dead) return;
    if (!api.runtime || !api.runtime.id) { teardown(); return; }
    try {
      var p = api.runtime.sendMessage(msg);
      if (p && p.catch) p.catch(function () {});
    } catch (e) { teardown(); }
  }

  function report() {
    if (!el) return;
    var s = readState(el);
    if (!s) return;
    send({ type: 'state', muted: s.muted, canUnmute: s.canUnmute });
  }

  function attach(found) {
    el = found;
    attrMo = new MutationObserver(function () { pending = null; report(); });
    attrMo.observe(el, { attributes: true });
    heartbeat = setInterval(report, HEARTBEAT_MS);
    report();
  }

  function detach() {
    if (!el) return;
    attrMo.disconnect();
    clearInterval(heartbeat);
    el = null; attrMo = null; heartbeat = null; pending = null;
    send({ type: 'bye' });
  }

  function scan() {
    if (dead) return;
    var found = document.getElementById('media-state');
    if (found === el) return;
    detach();
    if (found) attach(found);
  }

  function pressToggle() {
    window.dispatchEvent(new KeyboardEvent('keydown', {
      key: 'd', code: 'KeyD', ctrlKey: true, bubbles: true, cancelable: true,
    }));
  }

  api.runtime.onMessage.addListener(function (msg) {
    if (!msg || msg.type !== 'setMuted' || !el) return;
    var want = !!msg.value;
    if (planMute(readState(el), want, pending, Date.now()) !== 'press') return;
    pending = { muted: want, at: Date.now() };
    pressToggle();
    // Report the real state whether or not the press took (the attribute observer
    // also fires on success; this covers a press Visio ignored).
    setTimeout(report, VERIFY_MS);
  });

  docMo = new MutationObserver(scan);
  docMo.observe(document.documentElement, { childList: true, subtree: true });
  window.addEventListener('pagehide', detach);
  window.addEventListener('pageshow', scan);
  scan();
})();
