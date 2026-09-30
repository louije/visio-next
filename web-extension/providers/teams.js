/*
 * VisioNext — Microsoft Teams (web) provider for the call bridge (see call-bridge.js).
 *
 * The mic button's state is read from two language-independent attributes, cross-
 * checked: Microsoft's telemetry name for what a click will do
 * (`data-track-action-scenario`: callMuteAudio = live, callUnmuteAudio = muted) and
 * `data-state` (mic-off = muted). The English aria-label is only a last resort for
 * Teams variants without them; anything else is "unreadable", never a guess.
 * Verified live on teams.live.com (v2) 2026-09-30; other hooks from open-source bots.
 */
(function () {
  'use strict';

  var MIC = ['#microphone-button', '[data-inp="microphone-button"]', '#mic-button', '[data-tid="toggle-mute"]'];
  var HANGUP = ['#hangup-button', '[data-inp="hangup-button"]', '[data-tid="hangup-main-btn"]'];
  var PREJOIN = ['[data-tid="prejoin-join-button"]', '#prejoin-join-button'];

  function first(doc, selectors) {
    for (var k = 0; k < selectors.length; k++) {
      var el = doc.querySelector(selectors[k]);
      if (el) return el;
    }
    return null;
  }

  function isVisible(el) {
    return !!el && el.getClientRects().length > 0;
  }

  function isDisabled(el) {
    return !!el.disabled || el.getAttribute('aria-disabled') === 'true';
  }

  /** true/false, or null when unreadable. */
  function mutedFrom(mic) {
    var scenario = mic.getAttribute('data-track-action-scenario');
    var state = mic.getAttribute('data-state');
    var a = scenario === 'callUnmuteAudio' ? true : scenario === 'callMuteAudio' ? false : null;
    var b = state === null ? null : state === 'mic-off';
    if (a !== null && b !== null) return a === b ? a : null;
    if (a !== null) return a;
    if (b !== null) return b;
    var label = mic.getAttribute('aria-label') || '';
    if (/^unmute/i.test(label)) return true;
    if (/^mute/i.test(label)) return false;
    return null;
  }

  var provider = {
    id: 'teams',
    guardToggle: true,

    matches: function (host) {
      return host === 'teams.microsoft.com' || host === 'teams.cloud.microsoft' || host === 'teams.live.com';
    },

    /** null = not in a call; muted null = in a call, state unreadable. */
    read: function (doc) {
      var mic = first(doc, MIC);
      // The pre-join screen has a mic too: a call has a visible hangup button and no join button.
      if (!mic || !isVisible(first(doc, HANGUP)) || isVisible(first(doc, PREJOIN))) return null;
      return { muted: mutedFrom(mic), canUnmute: !isDisabled(mic) };
    },

    toggle: function (doc) {
      var mic = first(doc, MIC);
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
