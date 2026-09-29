// Unit tests for the pure parts of the call bridge. Run: node --test
const { test } = require('node:test');
const assert = require('node:assert');
const { readState, planMute, VERIFY_MS } = require('./call-bridge.js');

const el = (mic, canPublish) => ({
  dataset: { microphoneEnabled: mic, canPublishMicrophone: canPublish },
});

test('readState maps #media-state attributes', () => {
  assert.deepEqual(readState(el('true', 'true')), { muted: false, canUnmute: true });
  assert.deepEqual(readState(el('false', 'false')), { muted: true, canUnmute: false });
});

test('planMute presses only when the state must change', () => {
  assert.equal(planMute({ muted: false, canUnmute: true }, true, null, 0), 'press');
  assert.equal(planMute({ muted: true, canUnmute: true }, true, null, 0), 'skip');
  assert.equal(planMute({ muted: true, canUnmute: true }, false, null, 0), 'press');
  assert.equal(planMute({ muted: false, canUnmute: true }, false, null, 0), 'skip');
});

test('planMute never tries to unmute without permission', () => {
  assert.equal(planMute({ muted: true, canUnmute: false }, false, null, 0), 'skip');
});

test('planMute skips when not in a call', () => {
  assert.equal(planMute(null, true, null, 0), 'skip');
});

test('readState returns null for a missing or unknown attribute', () => {
  assert.equal(readState(el(undefined, 'true')), null);
  assert.equal(readState(el('maybe', 'true')), null);
});

test('planMute skips a repeat of a press still awaiting Visio', () => {
  const s = { muted: false, canUnmute: true };
  assert.equal(planMute(s, true, { muted: true, at: 0 }, VERIFY_MS - 1), 'skip');
});

test('planMute presses again once the pending window has passed', () => {
  const s = { muted: false, canUnmute: true };
  assert.equal(planMute(s, true, { muted: true, at: 0 }, VERIFY_MS), 'press');
});

test('planMute is not blocked by a pending press for the opposite target', () => {
  const s = { muted: true, canUnmute: true };
  assert.equal(planMute(s, false, { muted: true, at: 0 }, 10), 'press');
});
