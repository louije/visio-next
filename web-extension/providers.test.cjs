// Unit tests for the site adapters (providers/*.js). Run: node --test
const { test } = require('node:test');
const assert = require('node:assert');
const { el, doc, fakeWindow } = require('./fake-dom.cjs');
const visio = require('./providers/visio.js');

// ---- Visio ------------------------------------------------------------------

const mediaState = (mic, canPublish) =>
  el('div', { id: 'media-state', 'data-microphone-enabled': mic, 'data-can-publish-microphone': canPublish });

test('visio: matches its host only', () => {
  assert.equal(visio.matches('visio.numerique.gouv.fr'), true);
  assert.equal(visio.matches('meet.google.com'), false);
});

test('visio: not in a call without #media-state', () => {
  assert.equal(visio.read(doc([])), null);
});

test('visio: reads mute state and permission', () => {
  assert.deepEqual(visio.read(doc([mediaState('true', 'true')])), { muted: false, canUnmute: true });
  assert.deepEqual(visio.read(doc([mediaState('false', 'false')])), { muted: true, canUnmute: false });
});

test('visio: an unknown value is in a call but unreadable', () => {
  assert.deepEqual(visio.read(doc([mediaState('maybe', 'true')])), { muted: null, canUnmute: true });
});

test('visio: toggle presses Ctrl+D on the window', () => {
  const win = fakeWindow();
  assert.equal(visio.toggle(doc([mediaState('true', 'true')], win)), true);
  assert.equal(win.dispatched.length, 1);
  assert.equal(win.dispatched[0].type, 'keydown');
  assert.equal(win.dispatched[0].key, 'd');
  assert.equal(win.dispatched[0].ctrlKey, true);
});

test('visio: keeps a failed press from disabling toggles', () => {
  assert.equal(visio.guardToggle, false);
});
