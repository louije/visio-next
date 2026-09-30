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

// ---- Meet -------------------------------------------------------------------

const meet = require('./providers/meet.js');

const meetButton = (muted, iconName, opts) =>
  el('button', { 'data-is-muted': muted }, [el('i', { class: 'google-symbols notranslate' }, [], { text: iconName })], opts);
const panels = () => el('div', { 'data-panel-id': '1' });

test('meet: matches its host only', () => {
  assert.equal(meet.matches('meet.google.com'), true);
  assert.equal(meet.matches('visio.numerique.gouv.fr'), false);
});

test('meet: reads the mic in a call', () => {
  const live = doc([meetButton('false', 'mic'), meetButton('true', 'videocam_off'), panels()]);
  assert.deepEqual(meet.read(live), { muted: false, canUnmute: true });
  const muted = doc([meetButton('true', 'mic_off'), meetButton('false', 'videocam'), panels()]);
  assert.deepEqual(meet.read(muted), { muted: true, canUnmute: true });
});

test('meet: the pre-join screen (no side panels) is not a call', () => {
  assert.equal(meet.read(doc([meetButton('false', 'mic'), meetButton('false', 'videocam')])), null);
});

test('meet: finds the mic by its icon, not its position', () => {
  const d = doc([meetButton('false', 'videocam'), meetButton('true', 'mic_off'), panels()]);
  assert.deepEqual(meet.read(d), { muted: true, canUnmute: true });
});

test('meet: falls back to the first button when no icon names match', () => {
  const d = doc([meetButton('true', ''), meetButton('false', ''), panels()]);
  assert.deepEqual(meet.read(d), { muted: true, canUnmute: true });
});

test('meet: attribute and icon disagreeing is unreadable', () => {
  const d = doc([meetButton('false', 'mic_off'), panels()]);
  assert.deepEqual(meet.read(d), { muted: null, canUnmute: true });
});

test('meet: a disabled mic cannot be unmuted', () => {
  const d = doc([meetButton('true', 'mic_off', { disabled: true }), panels()]);
  assert.deepEqual(meet.read(d), { muted: true, canUnmute: false });
  const aria = doc([el('button', { 'data-is-muted': 'true', 'aria-disabled': 'true' }), panels()]);
  assert.equal(meet.read(aria).canUnmute, false);
});

test('meet: toggle clicks the mic, not the camera', () => {
  const cam = meetButton('false', 'videocam');
  const mic = meetButton('false', 'mic');
  assert.equal(meet.toggle(doc([cam, mic, panels()])), true);
  assert.equal(mic.clicks, 1);
  assert.equal(cam.clicks, 0);
});

test('meet: toggle reports failure without a mic', () => {
  assert.equal(meet.toggle(doc([panels()])), false);
});

test('meet: guards against clicking the wrong control', () => {
  assert.equal(meet.guardToggle, true);
});
