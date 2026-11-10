import http from 'node:http';
import { pathToFileURL } from 'node:url';

const DEFAULT_PORT = 11435;
const DEFAULT_UPSTREAM = 'http://host.docker.internal:11434';
const DEFAULT_REASONING_EFFORT = 'low';
const MAX_REQUEST_BYTES = 32 * 1024 * 1024;

const toolCallCache = new Map();

function normalizeToolCall(call) {
  const id = call?.id;
  const name = call?.function?.name;
  if (!id || !name) return null;

  return {
    id: String(id),
    type: 'function',
    function: {
      name: String(name),
      arguments:
        typeof call.function.arguments === 'string'
          ? call.function.arguments
          : JSON.stringify(call.function.arguments ?? {}),
    },
  };
}

function messageToolCalls(message) {
  if (!Array.isArray(message?.tool_calls)) return [];
  return message.tool_calls.map(normalizeToolCall).filter(Boolean);
}

export function sanitizeMessages(messages, cache = toolCallCache) {
  if (!Array.isArray(messages)) {
    return { messages, repaired: 0, canonicalized: 0, dropped: 0 };
  }

  const output = [];
  let repaired = 0;
  let canonicalized = 0;
  let dropped = 0;

  for (const original of messages) {
    const message = structuredClone(original);

    if (message.role === 'assistant') {
      if (message.reasoning_content && !message.reasoning) {
        message.reasoning = message.reasoning_content;
      }
      delete message.reasoning_content;

      const calls = messageToolCalls(message);
      if (calls.length > 0) {
        message.tool_calls = calls;
        for (const call of calls) cache.set(call.id, call);
      }

      output.push(message);
      continue;
    }

    if (message.role !== 'tool') {
      output.push(message);
      continue;
    }

    const callId = message.tool_call_id;
    const previous = output.at(-1);
    const previousCalls = messageToolCalls(previous);
    const previousMatch = previousCalls.find((call) => call.id === callId);

    if (previousMatch) {
      const canonicalAssistant = {
        role: 'assistant',
        content: null,
        tool_calls: [previousMatch],
      };
      if (previous.reasoning) canonicalAssistant.reasoning = previous.reasoning;

      output[output.length - 1] = canonicalAssistant;
      message.name = previousMatch.function.name;
      output.push(message);
      canonicalized += 1;
      continue;
    }

    const matchingCall = previousMatch ?? cache.get(callId);
    if (!matchingCall) {
      dropped += 1;
      continue;
    }

    const syntheticAssistant = {
      role: 'assistant',
      content: null,
      tool_calls: [matchingCall],
    };

    if (previousMatch && previous?.role === 'assistant') {
      if (previous.reasoning) syntheticAssistant.reasoning = previous.reasoning;
      if (previous.content) syntheticAssistant.content = previous.content;
      output[output.length - 1] = syntheticAssistant;
    } else {
      output.push(syntheticAssistant);
    }

    message.name = matchingCall.function.name;
    output.push(message);
    repaired += 1;
  }

  return { messages: output, repaired, canonicalized, dropped };
}

function stringifyToolContent(content) {
  if (typeof content === 'string') return content;
  return JSON.stringify(content ?? null);
}

export function flattenToolHistory(messages, cache = toolCallCache) {
  if (!Array.isArray(messages)) {
    return { messages, flattened: 0 };
  }

  const output = [];
  let flattened = 0;

  for (const message of messages) {
    if (message.role === 'assistant' && messageToolCalls(message).length > 0) {
      for (const call of messageToolCalls(message)) cache.set(call.id, call);

      if (typeof message.content === 'string' && message.content.trim()) {
        output.push({ role: 'assistant', content: message.content });
      }
      continue;
    }

    if (message.role === 'tool') {
      const call = cache.get(message.tool_call_id);
      const name = message.name || call?.function?.name || 'unknown_tool';
      output.push({
        role: 'user',
        content: `[Tool result: ${name}]\n${stringifyToolContent(message.content)}`,
      });
      flattened += 1;
      continue;
    }

    output.push(message);
  }

  return { messages: output, flattened };
}

function cacheToolCallsFromJson(payload, cache = toolCallCache) {
  const calls = payload?.choices?.[0]?.message?.tool_calls;
  if (!Array.isArray(calls)) return;

  for (const call of calls) {
    const normalized = normalizeToolCall(call);
    if (normalized) cache.set(normalized.id, normalized);
  }
}

function cacheToolCallsFromSse(text, cache = toolCallCache) {
  const callsByIndex = new Map();

  for (const line of text.split(/\r?\n/)) {
    if (!line.startsWith('data:')) continue;
    const data = line.slice(5).trim();
    if (!data || data === '[DONE]') continue;

    let payload;
    try {
      payload = JSON.parse(data);
    } catch {
      continue;
    }

    const deltas = payload?.choices?.[0]?.delta?.tool_calls;
    if (!Array.isArray(deltas)) continue;

    for (const delta of deltas) {
      const index = Number.isInteger(delta.index) ? delta.index : 0;
      let state = callsByIndex.get(index);

      if (delta.id && (!state || state.id !== delta.id)) {
        state = {
          id: String(delta.id),
          type: 'function',
          function: { name: '', arguments: '' },
        };
        callsByIndex.set(index, state);
      }

      if (!state) continue;
      if (delta.function?.name) state.function.name += delta.function.name;
      if (delta.function?.arguments) {
        state.function.arguments += delta.function.arguments;
      }
    }
  }

  for (const call of callsByIndex.values()) {
    const normalized = normalizeToolCall(call);
    if (normalized) cache.set(normalized.id, normalized);
  }
}

function cacheResponseToolCalls(buffer, contentType) {
  const text = buffer.toString('utf8');

  if (contentType.includes('text/event-stream')) {
    cacheToolCallsFromSse(text);
    return;
  }

  if (contentType.includes('application/json')) {
    try {
      cacheToolCallsFromJson(JSON.parse(text));
    } catch {
      // Upstream errors can contain non-JSON bodies. They pass through unchanged.
    }
  }
}

function forwardHeaders(headers) {
  const forwarded = {};
  for (const [name, value] of Object.entries(headers)) {
    if (
      value === undefined ||
      ['host', 'connection', 'content-length', 'transfer-encoding', 'accept-encoding'].includes(
        name.toLowerCase(),
      )
    ) {
      continue;
    }
    forwarded[name] = Array.isArray(value) ? value.join(', ') : value;
  }
  return forwarded;
}

async function readBody(request) {
  const chunks = [];
  let size = 0;

  for await (const chunk of request) {
    size += chunk.length;
    if (size > MAX_REQUEST_BYTES) throw new Error('request body too large');
    chunks.push(chunk);
  }

  return Buffer.concat(chunks);
}

export function startServer({
  port = Number(process.env.PORT || DEFAULT_PORT),
  upstream = process.env.OLLAMA_BASE_URL || DEFAULT_UPSTREAM,
  reasoningEffort = process.env.REASONING_EFFORT || DEFAULT_REASONING_EFFORT,
} = {}) {
  const server = http.createServer(async (request, response) => {
    if (request.url === '/healthz') {
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end('{"status":"ok"}');
      return;
    }

    try {
      const rawBody = await readBody(request);
      let body = rawBody;

      if (
        request.method === 'POST' &&
        request.url?.endsWith('/v1/chat/completions') &&
        rawBody.length > 0
      ) {
        const payload = JSON.parse(rawBody.toString('utf8'));
        const sanitized = sanitizeMessages(payload.messages);
        const flattened = flattenToolHistory(sanitized.messages);
        payload.messages = flattened.messages;
        payload.reasoning_effort = reasoningEffort;
        body = Buffer.from(JSON.stringify(payload));

        console.log(
          JSON.stringify({
            path: request.url,
            messages: payload.messages.map((message) => ({
              role: message.role,
              contentType:
                message.content === null
                  ? 'null'
                  : Array.isArray(message.content)
                    ? 'array'
                    : typeof message.content,
              reasoning: Boolean(message.reasoning),
              toolCalls: messageToolCalls(message).map((call) => ({
                id: call.id,
                name: call.function.name,
              })),
              toolCallId: message.tool_call_id,
              name: message.name,
            })),
            repaired: sanitized.repaired,
            canonicalized: sanitized.canonicalized,
            dropped: sanitized.dropped,
            flattened: flattened.flattened,
            reasoningEffort,
          }),
        );
      }

      const upstreamResponse = await fetch(new URL(request.url, upstream), {
        method: request.method,
        headers: forwardHeaders(request.headers),
        body: ['GET', 'HEAD'].includes(request.method ?? 'GET') ? undefined : body,
      });

      const responseBody = Buffer.from(await upstreamResponse.arrayBuffer());
      const contentType = upstreamResponse.headers.get('content-type') ?? '';
      cacheResponseToolCalls(responseBody, contentType);

      const responseHeaders = {};
      for (const [name, value] of upstreamResponse.headers.entries()) {
        if (['content-length', 'content-encoding', 'transfer-encoding'].includes(name)) {
          continue;
        }
        responseHeaders[name] = value;
      }

      response.writeHead(upstreamResponse.status, responseHeaders);
      response.end(responseBody);
    } catch (error) {
      console.error(error);
      response.writeHead(502, { 'content-type': 'application/json' });
      response.end(
        JSON.stringify({
          error: {
            message: error instanceof Error ? error.message : String(error),
            type: 'adapter_error',
          },
        }),
      );
    }
  });

  server.listen(port, '0.0.0.0', () => {
    console.log(`ollama-adapter listening on ${port}, upstream ${upstream}`);
  });

  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  startServer();
}
