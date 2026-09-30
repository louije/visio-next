/*
 * VisioNext — Visio provider for the call bridge (see call-bridge.js).
 *
 * Visio renders a hidden `#media-state` element, only in a room and meant for external
 * tools. Muting presses Visio's Ctrl+D shortcut: its listener sits on `window` and
 * ignores focus, and an event dispatched on `window` never passes through the chat
 * textarea that swallows real keypresses.
 */
(function () {
  'use strict';

  var provider = {
    id: 'visio',
    // A press Visio refuses (mic in use…) mustn't disable pressing for the whole call.
    guardToggle: false,

    matches: function (host) {
      return host === 'visio.numerique.gouv.fr';
    },

    /** null = not in a call; muted null = in a call, state unreadable. */
    read: function (doc) {
      var el = doc.querySelector('#media-state');
      if (!el) return null;
      var mic = el.getAttribute('data-microphone-enabled');
      return {
        muted: mic === 'true' ? false : mic === 'false' ? true : null,
        canUnmute: el.getAttribute('data-can-publish-microphone') !== 'false',
      };
    },

    toggle: function (doc) {
      var win = doc.defaultView;
      win.dispatchEvent(new win.KeyboardEvent('keydown', {
        key: 'd', code: 'KeyD', ctrlKey: true, bubbles: true, cancelable: true,
      }));
      return true;
    },
  };

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = provider;
  } else {
    var list = globalThis.__vnProviders = globalThis.__vnProviders || [];
    var at = -1;
    for (var k = 0; k < list.length; k++) if (list[k].id === provider.id) at = k;
    if (at >= 0) list[at] = provider; else list.push(provider);
  }
})();
