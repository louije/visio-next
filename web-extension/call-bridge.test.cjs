// Unit tests for the pure parts of the call bridge core. Run: node --test
const { test } = require('node:test');
const assert = require('node:assert');
const { planMute, sameState, pickProvider } = require('./call-bridge.js');

test('planMute presses only when the state must change', () => {
  assert.equal(planMute({ muted: false, canUnmute: true }, true, null), 'press');
  assert.equal(planMute({ muted: true, canUnmute: true }, true, null), 'skip');
  assert.equal(planMute({ muted: true, canUnmute: true }, false, null), 'press');
  assert.equal(planMute({ muted: false, canUnmute: true }, false, null), 'skip');
});

test('planMute never tries to unmute without permission', () => {
  assert.equal(planMute({ muted: true, canUnmute: false }, false, null), 'skip');
});

test('planMute skips when not in a call or the state is unreadable', () => {
  assert.equal(planMute(null, true, null), 'skip');
  assert.equal(planMute({ muted: null, canUnmute: true }, true, null), 'skip');
});

test('planMute skips a repeat for as long as the press is pending, however slow the page', () => {
  // The core always clears `pending` (matching read, verify, second check, leaving the
  // call), so there's no need for a time limit, and a slow page can't be toggled back.
  const s = { muted: false, canUnmute: true };
  assert.equal(planMute(s, true, { muted: true }), 'skip');
});

test('planMute is not blocked by a pending press for the opposite target', () => {
  const s = { muted: true, canUnmute: true };
  assert.equal(planMute(s, false, { muted: true }), 'press');
});

test('sameState compares what the app sees', () => {
  assert.equal(sameState({ muted: true, canUnmute: true }, { muted: true, canUnmute: true }), true);
  assert.equal(sameState({ muted: true, canUnmute: true }, { muted: false, canUnmute: true }), false);
  assert.equal(sameState({ muted: true, canUnmute: true }, { muted: true, canUnmute: false }), false);
  assert.equal(sameState(null, { muted: true, canUnmute: true }), false);
});

test('pickProvider picks the one matching the host', () => {
  const a = { id: 'a', matches: (h) => h === 'a.test' };
  const b = { id: 'b', matches: (h) => h === 'b.test' };
  assert.equal(pickProvider([a, b], 'b.test'), b);
  assert.equal(pickProvider([a, b], 'c.test'), null);
});
