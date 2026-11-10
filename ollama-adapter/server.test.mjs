import assert from 'node:assert/strict';
import { once } from 'node:events';
import http from 'node:http';
import test from 'node:test';

import {
  flattenToolHistory,
  resolveUpstreamUrl,
  sanitizeMessages,
  startServer,
  ToolCallCache,
} from './server.mjs';

const call = {
  id: 'call-1',
  type: 'function',
  function: { name: 'example_tool', arguments: '{"value":1}' },
};

async function listen(server) {
  if (!server.listening) await once(server, 'listening');
  return server.address().port;
}

function close(server) {
  if (!server.listening) return;
  server.closeAllConnections?.();
  server.close();
  server.unref();
}

test('preserves a valid assistant/tool pair', () => {
  const result = sanitizeMessages(
    [
      { role: 'assistant', content: null, tool_calls: [call] },
      { role: 'tool', tool_call_id: 'call-1', content: '{"ok":true}' },
    ],
    new Map(),
  );

  assert.equal(result.repaired, 0);
  assert.equal(result.canonicalized, 1);
  assert.equal(result.dropped, 0);
  assert.deepEqual(result.messages.map((message) => message.role), ['assistant', 'tool']);
  assert.equal(result.messages[1].name, 'example_tool');
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
  assert.equal(result.canonicalized, 0);
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
  assert.equal(result.canonicalized, 0);
  assert.equal(result.dropped, 0);
  assert.deepEqual(result.messages.map((message) => message.role), ['assistant', 'tool']);
});

test('drops an unrecoverable orphan instead of crashing Ollama', () => {
  const result = sanitizeMessages(
    [{ role: 'tool', tool_call_id: 'missing', content: '{"ok":true}' }],
    new Map(),
  );

  assert.equal(result.repaired, 0);
  assert.equal(result.canonicalized, 0);
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

  assert.equal(result.repaired, 1);
  assert.equal(result.canonicalized, 1);
  assert.deepEqual(result.messages.map((message) => message.role), [
    'assistant',
    'tool',
    'assistant',
    'tool',
  ]);
  assert.equal(result.messages[0].tool_calls[0].id, 'call-1');
  assert.equal(result.messages[2].tool_calls[0].id, 'call-2');
});

test('flattens completed tool turns for strict GGUF chat templates', () => {
  const cache = new Map();
  const sanitized = sanitizeMessages(
    [
      { role: 'system', content: 'System instructions' },
      { role: 'user', content: 'Use the tool' },
      {
        role: 'assistant',
        content: null,
        reasoning_content: 'Need a tool.',
        tool_calls: [call],
      },
      { role: 'tool', tool_call_id: 'call-1', content: '{"ok":true}' },
    ],
    cache,
  );
  const result = flattenToolHistory(sanitized.messages, cache);

  assert.equal(result.flattened, 1);
  assert.deepEqual(result.messages.map((message) => message.role), [
    'system',
    'user',
    'user',
  ]);
  assert.match(result.messages[2].content, /^\[Tool result: example_tool\]/);
  assert.match(result.messages[2].content, /"ok":true/);
});

test('bounds cached tool calls by size and TTL', () => {
  let now = 0;
  const cache = new ToolCallCache({ maxEntries: 2, ttlMs: 100, now: () => now });
  cache.set('call-1', call);
  cache.set('call-2', { ...call, id: 'call-2' });
  cache.set('call-3', { ...call, id: 'call-3' });

  assert.equal(cache.size, 2);
  assert.equal(cache.get('call-1'), undefined);
  assert.equal(cache.get('call-2').id, 'call-2');

  now = 101;
  assert.equal(cache.get('call-2'), undefined);
  assert.equal(cache.size, 0);
});

test('preserves assistant text while canonicalizing a tool call', () => {
  const result = sanitizeMessages(
    [
      {
        role: 'assistant',
        content: 'Useful context',
        reasoning: 'Hidden reasoning',
        tool_calls: [call],
      },
      { role: 'tool', tool_call_id: 'call-1', content: '{"ok":true}' },
    ],
    new Map(),
  );

  assert.equal(result.messages[0].content, 'Useful context');
  assert.equal('reasoning' in result.messages[0], false);
});

test('keeps upstream requests on the configured origin', () => {
  assert.equal(
    resolveUpstreamUrl('/v1/models?limit=1', 'http://ollama:11434').href,
    'http://ollama:11434/v1/models?limit=1',
  );
  assert.throws(
    () => resolveUpstreamUrl('http://169.254.169.254/latest/meta-data', 'http://ollama:11434'),
    /invalid request target/,
  );
  assert.throws(
    () => resolveUpstreamUrl('//169.254.169.254/latest/meta-data', 'http://ollama:11434'),
    /invalid request target/,
  );
});

test('returns 413 when the request body exceeds the configured limit', async (t) => {
  const adapter = startServer({
    port: 0,
    upstream: 'http://127.0.0.1:1',
    maxRequestBytes: 4,
  });
  t.after(() => close(adapter));
  const port = await listen(adapter);

  const response = await fetch(`http://127.0.0.1:${port}/v1/chat/completions`, {
    method: 'POST',
    body: '12345',
  });

  assert.equal(response.status, 413);
  assert.equal((await response.json()).error.type, 'invalid_request_error');
});

test('forwards requests without a messages array unchanged', async (t) => {
  let received;
  const upstream = http.createServer(async (request, response) => {
    let body = '';
    for await (const chunk of request) body += chunk;
    received = JSON.parse(body);
    response.writeHead(400, { 'content-type': 'application/json' });
    response.end('{"error":{"message":"messages is required"}}');
  });
  t.after(() => close(upstream));
  upstream.listen(0, '127.0.0.1');
  const upstreamPort = await listen(upstream);

  const adapter = startServer({
    port: 0,
    upstream: `http://127.0.0.1:${upstreamPort}`,
  });
  t.after(() => close(adapter));
  const adapterPort = await listen(adapter);

  const requestBody = { model: 'test-model' };
  const response = await fetch(`http://127.0.0.1:${adapterPort}/v1/chat/completions`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(requestBody),
  });

  assert.equal(response.status, 400);
  assert.deepEqual(received, requestBody);
});

test('streams SSE chunks without buffering the complete response', async (t) => {
  let upstreamEnded = false;
  const upstream = http.createServer((_request, response) => {
    response.writeHead(200, { 'content-type': 'text/event-stream' });
    response.write('data: {"choices":[{"delta":{"content":"first"}}]}\\n\\n');
    setTimeout(() => {
      response.end('data: [DONE]\\n\\n');
      upstreamEnded = true;
    }, 75);
  });
  t.after(() => close(upstream));
  upstream.listen(0, '127.0.0.1');
  const upstreamPort = await listen(upstream);

  const adapter = startServer({
    port: 0,
    upstream: `http://127.0.0.1:${upstreamPort}`,
  });
  t.after(() => close(adapter));
  const adapterPort = await listen(adapter);

  const response = await fetch(`http://127.0.0.1:${adapterPort}/v1/chat/completions`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ model: 'test-model', messages: [] }),
  });
  const reader = response.body.getReader();
  const firstChunk = await reader.read();

  assert.equal(response.status, 200);
  assert.equal(upstreamEnded, false);
  assert.match(new TextDecoder().decode(firstChunk.value), /first/);

  while (!(await reader.read()).done) {
    // Drain the remaining stream so the adapter can finish cleanly.
  }
  assert.equal(upstreamEnded, true);
});
