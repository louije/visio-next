// Unit tests for the pure parts of the call bridge. Run: node --test
const { test } = require('node:test');
const assert = require('node:assert');
const { readState, planMute } = require('./call-bridge.js');

const el = (mic, canPublish) => ({
  dataset: { microphoneEnabled: mic, canPublishMicrophone: canPublish },
});

test('readState maps #media-state attributes', () => {
  assert.deepEqual(readState(el('true', 'true')), { muted: false, canUnmute: true });
  assert.deepEqual(readState(el('false', 'false')), { muted: true, canUnmute: false });
});

test('planMute presses only when the state must change', () => {
  assert.equal(planMute({ muted: false, canUnmute: true }, true), 'press');
  assert.equal(planMute({ muted: true, canUnmute: true }, true), 'skip');
  assert.equal(planMute({ muted: true, canUnmute: true }, false), 'press');
  assert.equal(planMute({ muted: false, canUnmute: true }, false), 'skip');
});

test('planMute never tries to unmute without permission', () => {
  assert.equal(planMute({ muted: true, canUnmute: false }, false), 'skip');
});

test('planMute skips when not in a call', () => {
  assert.equal(planMute(null, true), 'skip');
});
