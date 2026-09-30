/*
 * VisioNext — Google Meet provider for the call bridge (see call-bridge.js).
 *
 * Only semantic attributes and Google's public icon names — never Meet's minified
 * `jsname` identifiers, which change. The mic and camera buttons carry
 * `data-is-muted`; their Material Symbols icon (`i.google-symbols`, whose text is the
 * ligature name) tells them apart: `mic` / `mic_off` vs `videocam` / `videocam_off`.
 * Meet replaces these elements rather than updating them, so nothing is cached.
 * Verified live 2026-09-30.
 */
(function () {
  'use strict';

  function iconName(button) {
    var i = button.querySelector('i.google-symbols');
    return i ? String(i.textContent).trim() : '';
  }

  /** The mic among the [data-is-muted] buttons; else the first non-camera one. */
  function findMic(doc) {
    var buttons = doc.querySelectorAll('button[data-is-muted]');
    for (var k = 0; k < buttons.length; k++) {
      if (/^mic/.test(iconName(buttons[k]))) return buttons[k];
    }
    // No mic icon: the first button that is certainly not the camera.
    for (var j = 0; j < buttons.length; j++) {
      if (!/^videocam/.test(iconName(buttons[j]))) return buttons[j];
    }
    return null;
  }

  function isDisabled(el) {
    return !!el.disabled || el.getAttribute('aria-disabled') === 'true';
  }

  var provider = {
    id: 'meet',
    guardToggle: true,

    matches: function (host) {
      return host === 'meet.google.com';
    },

    /** null = not in a call; muted null = in a call, state unreadable. */
    read: function (doc) {
      var mic = findMic(doc);
      // The pre-join screen has the mic too, but not the call's side panels.
      if (!mic || !doc.querySelector('[data-panel-id]')) return null;
      var attr = mic.getAttribute('data-is-muted');
      var muted = attr === 'true' ? true : attr === 'false' ? false : null;
      var icon = iconName(mic);
      // Two readings of the same state; if they disagree (e.g. the ~200 ms after a
      // screen change when Meet renders data-is-muted="false" first), wait.
      if (muted !== null && /^mic/.test(icon) && (icon === 'mic_off') !== muted) muted = null;
      return { muted: muted, canUnmute: !isDisabled(mic) };
    },

    toggle: function (doc) {
      var mic = findMic(doc);
      if (!mic) return false;
      mic.click();
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
