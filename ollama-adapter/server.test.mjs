import assert from 'node:assert/strict';
import test from 'node:test';

import { sanitizeMessages } from './server.mjs';

const call = {
  id: 'call-1',
  type: 'function',
  function: { name: 'example_tool', arguments: '{"value":1}' },
};

test('preserves a valid assistant/tool pair', () => {
  const result = sanitizeMessages(
    [
      { role: 'assistant', content: null, tool_calls: [call] },
      { role: 'tool', tool_call_id: 'call-1', content: '{"ok":true}' },
    ],
    new Map(),
  );

  assert.equal(result.repaired, 0);
  assert.equal(result.dropped, 0);
  assert.deepEqual(result.messages.map((message) => message.role), ['assistant', 'tool']);
});

test('moves provider reasoning to Ollamas reasoning field', () => {
  const result = sanitizeMessages(
    [
      {
        role: 'assistant',
        content: null,
        reasoning_content: 'Need a tool.',
        tool_calls: [call],
      },
    ],
    new Map(),
  );

  assert.equal(result.messages[0].reasoning, 'Need a tool.');
  assert.equal('reasoning_content' in result.messages[0], false);
});

test('repairs a separated tool result from the request history', () => {
  const result = sanitizeMessages(
    [
      { role: 'assistant', content: null, tool_calls: [call] },
      { role: 'assistant', content: 'intermediate message' },
      { role: 'tool', tool_call_id: 'call-1', content: '{"ok":true}' },
    ],
    new Map(),
  );

  assert.equal(result.repaired, 1);
  assert.equal(result.dropped, 0);
  assert.deepEqual(result.messages.slice(-2).map((message) => message.role), [
    'assistant',
    'tool',
  ]);
  assert.deepEqual(result.messages.at(-2).tool_calls, [call]);
});

test('repairs a tool result from the cross-request cache', () => {
  const cache = new Map([['call-1', call]]);
  const result = sanitizeMessages(
    [{ role: 'tool', tool_call_id: 'call-1', content: '{"ok":true}' }],
    cache,
  );

  assert.equal(result.repaired, 1);
  assert.equal(result.dropped, 0);
  assert.deepEqual(result.messages.map((message) => message.role), ['assistant', 'tool']);
});

test('drops an unrecoverable orphan instead of crashing Ollama', () => {
  const result = sanitizeMessages(
    [{ role: 'tool', tool_call_id: 'missing', content: '{"ok":true}' }],
    new Map(),
  );

  assert.equal(result.repaired, 0);
  assert.equal(result.dropped, 1);
  assert.deepEqual(result.messages, []);
});

test('splits multiple tool results into Harmony-compatible pairs', () => {
  const secondCall = {
    id: 'call-2',
    type: 'function',
    function: { name: 'second_tool', arguments: '{}' },
  };
  const result = sanitizeMessages(
    [
      { role: 'assistant', content: null, tool_calls: [call, secondCall] },
      { role: 'tool', tool_call_id: 'call-1', content: 'first' },
      { role: 'tool', tool_call_id: 'call-2', content: 'second' },
    ],
    new Map(),
  );

  assert.equal(result.repaired, 2);
  assert.deepEqual(result.messages.map((message) => message.role), [
    'assistant',
    'tool',
    'assistant',
    'tool',
  ]);
  assert.equal(result.messages[0].tool_calls[0].id, 'call-1');
  assert.equal(result.messages[2].tool_calls[0].id, 'call-2');
});
