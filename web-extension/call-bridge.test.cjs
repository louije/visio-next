// Unit tests for the pure parts of the call bridge core. Run: node --test
const { test } = require('node:test');
const assert = require('node:assert');
const { planMute, sameState, pickProvider, VERIFY_MS } = require('./call-bridge.js');

test('planMute presses only when the state must change', () => {
  assert.equal(planMute({ muted: false, canUnmute: true }, true, null, 0), 'press');
  assert.equal(planMute({ muted: true, canUnmute: true }, true, null, 0), 'skip');
  assert.equal(planMute({ muted: true, canUnmute: true }, false, null, 0), 'press');
  assert.equal(planMute({ muted: false, canUnmute: true }, false, null, 0), 'skip');
});

test('planMute never tries to unmute without permission', () => {
  assert.equal(planMute({ muted: true, canUnmute: false }, false, null, 0), 'skip');
});

test('planMute skips when not in a call or the state is unreadable', () => {
  assert.equal(planMute(null, true, null, 0), 'skip');
  assert.equal(planMute({ muted: null, canUnmute: true }, true, null, 0), 'skip');
});

test('planMute skips a repeat of a press still awaiting the page', () => {
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
