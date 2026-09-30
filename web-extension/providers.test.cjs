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

// ---- Teams ------------------------------------------------------------------

const teams = require('./providers/teams.js');

const LIVE = { 'data-track-action-scenario': 'callMuteAudio', 'data-state': 'mic-volume-renderer', 'aria-label': 'Mute mic' };
const MUTED = { 'data-track-action-scenario': 'callUnmuteAudio', 'data-state': 'mic-off', 'aria-label': 'Unmute mic' };
const teamsMic = (attrs, opts) => el('button', Object.assign({ id: 'microphone-button', 'data-inp': 'microphone-button' }, attrs), [], opts);
const hangup = (opts) => el('button', { id: 'hangup-button', 'data-tid': 'hangup-main-btn' }, [], opts);

test('teams: matches its hosts', () => {
  assert.equal(teams.matches('teams.microsoft.com'), true);
  assert.equal(teams.matches('teams.cloud.microsoft'), true);
  assert.equal(teams.matches('teams.live.com'), true);
  assert.equal(teams.matches('meet.google.com'), false);
});

test('teams: reads the mic in a call', () => {
  assert.deepEqual(teams.read(doc([teamsMic(LIVE), hangup()])), { muted: false, canUnmute: true });
  assert.deepEqual(teams.read(doc([teamsMic(MUTED), hangup()])), { muted: true, canUnmute: true });
});

test('teams: not a call without a visible hangup button, or on the pre-join screen', () => {
  assert.equal(teams.read(doc([teamsMic(LIVE)])), null);
  assert.equal(teams.read(doc([teamsMic(LIVE), hangup({ hidden: true })])), null);
  const prejoin = el('button', { 'data-tid': 'prejoin-join-button' });
  assert.equal(teams.read(doc([teamsMic(LIVE), hangup(), prejoin])), null);
});

test('teams: state from either language-independent signal alone', () => {
  assert.equal(teams.read(doc([teamsMic({ 'data-state': 'mic-off' }), hangup()])).muted, true);
  assert.equal(teams.read(doc([teamsMic({ 'data-track-action-scenario': 'callMuteAudio' }), hangup()])).muted, false);
});

test('teams: the two signals disagreeing is unreadable', () => {
  const d = doc([teamsMic({ 'data-track-action-scenario': 'callMuteAudio', 'data-state': 'mic-off' }), hangup()]);
  assert.equal(teams.read(d).muted, null);
});

test('teams: falls back to the English label, else unreadable', () => {
  assert.equal(teams.read(doc([teamsMic({ 'aria-label': 'Unmute mic' }), hangup()])).muted, true);
  assert.equal(teams.read(doc([teamsMic({ 'aria-label': 'Mute mic' }), hangup()])).muted, false);
  assert.equal(teams.read(doc([teamsMic({ 'aria-label': 'Couper le micro' }), hangup()])).muted, null);
});

test('teams: finds the mic by its other known hooks', () => {
  const byInp = el('button', Object.assign({ 'data-inp': 'microphone-button' }, MUTED));
  assert.equal(teams.read(doc([byInp, hangup()])).muted, true);
  const byTid = el('button', Object.assign({ 'data-tid': 'toggle-mute' }, LIVE));
  const hangupByInp = el('button', { 'data-inp': 'hangup-button' });
  assert.equal(teams.read(doc([byTid, hangupByInp])).muted, false);
});

test('teams: a disabled mic cannot be unmuted', () => {
  assert.equal(teams.read(doc([teamsMic(MUTED, { disabled: true }), hangup()])).canUnmute, false);
});

test('teams: toggle clicks the mic', () => {
  const mic = teamsMic(LIVE);
  assert.equal(teams.toggle(doc([mic, hangup()])), true);
  assert.equal(mic.clicks, 1);
  assert.equal(teams.toggle(doc([hangup()])), false);
});

test('teams: guards against clicking the wrong control', () => {
  assert.equal(teams.guardToggle, true);
});
