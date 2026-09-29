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

  function readState(el) {
    return {
      muted: el.dataset.microphoneEnabled !== 'true',
      canUnmute: el.dataset.canPublishMicrophone !== 'false',
    };
  }

  /** 'press' when Ctrl+D must be sent to reach `wantMuted`, else 'skip'. */
  function planMute(state, wantMuted) {
    if (!state) return 'skip';
    if (state.muted === wantMuted) return 'skip';
    if (!wantMuted && !state.canUnmute) return 'skip';
    return 'press';
  }

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { readState: readState, planMute: planMute };
  }

  // ---- DOM + messaging (extension only) ------------------------------------
  if (typeof document === 'undefined') return;
  var api = (typeof browser !== 'undefined') ? browser
    : (typeof chrome !== 'undefined') ? chrome : null;
  if (!api || !api.runtime) return;

  var HEARTBEAT_MS = 30000;
  var VERIFY_MS = 1000;
  var el = null;
  var attrMo = null;
  var heartbeat = null;

  function send(msg) {
    try {
      var p = api.runtime.sendMessage(msg);
      if (p && p.catch) p.catch(function () {});
    } catch (e) { /* extension reloaded: this page's script is orphaned */ }
  }

  function report() {
    if (!el) return;
    var s = readState(el);
    send({ type: 'state', muted: s.muted, canUnmute: s.canUnmute });
  }

  function attach(found) {
    el = found;
    attrMo = new MutationObserver(report);
    attrMo.observe(el, { attributes: true });
    heartbeat = setInterval(report, HEARTBEAT_MS);
    report();
  }

  function detach() {
    if (!el) return;
    attrMo.disconnect();
    clearInterval(heartbeat);
    el = null; attrMo = null; heartbeat = null;
    send({ type: 'bye' });
  }

  function scan() {
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
    if (planMute(readState(el), !!msg.value) !== 'press') return;
    pressToggle();
    // Report the real state whether or not the press took (the attribute observer
    // also fires on success; this covers a press Visio ignored).
    setTimeout(report, VERIFY_MS);
  });

  new MutationObserver(scan).observe(document.documentElement, { childList: true, subtree: true });
  window.addEventListener('pagehide', detach);
  scan();
})();
