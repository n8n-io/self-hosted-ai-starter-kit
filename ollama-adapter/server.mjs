import http from 'node:http';
import { pathToFileURL } from 'node:url';

const DEFAULT_PORT = 11435;
const DEFAULT_UPSTREAM = 'http://host.docker.internal:11434';
const DEFAULT_REASONING_EFFORT = 'low';
const MAX_REQUEST_BYTES = 32 * 1024 * 1024;
const MAX_JSON_CAPTURE_BYTES = 1024 * 1024;
const MAX_CACHE_ENTRIES = 2048;
const CACHE_TTL_MS = 15 * 60 * 1000;

export class ToolCallCache {
  #entries = new Map();

  constructor({
    maxEntries = MAX_CACHE_ENTRIES,
    ttlMs = CACHE_TTL_MS,
    now = () => Date.now(),
  } = {}) {
    this.maxEntries = maxEntries;
    this.ttlMs = ttlMs;
    this.now = now;
  }

  get size() {
    this.#pruneExpired();
    return this.#entries.size;
  }

  get(id) {
    const entry = this.#entries.get(id);
    if (!entry) return undefined;
    if (entry.expiresAt <= this.now()) {
      this.#entries.delete(id);
      return undefined;
    }
    return entry.call;
  }

  set(id, call) {
    this.#pruneExpired();
    this.#entries.delete(id);
    this.#entries.set(id, { call, expiresAt: this.now() + this.ttlMs });

    while (this.#entries.size > this.maxEntries) {
      this.#entries.delete(this.#entries.keys().next().value);
    }
    return this;
  }

  #pruneExpired() {
    const now = this.now();
    for (const [id, entry] of this.#entries) {
      if (entry.expiresAt <= now) this.#entries.delete(id);
    }
  }
}

const toolCallCache = new ToolCallCache();

class HttpError extends Error {
  constructor(statusCode, message) {
    super(message);
    this.statusCode = statusCode;
  }
}

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
      const hasContent =
        (typeof previous.content === 'string' && previous.content.length > 0) ||
        (Array.isArray(previous.content) && previous.content.length > 0);
      const canonicalAssistant = {
        role: 'assistant',
        content: hasContent ? previous.content : null,
        tool_calls: [previousMatch],
      };
      if (!hasContent && previous.reasoning) {
        canonicalAssistant.reasoning = previous.reasoning;
      }

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
    output.push(syntheticAssistant);

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

function collectSseToolCalls(line, callsByIndex) {
  if (!line.startsWith('data:')) return;
  const data = line.slice(5).trim();
  if (!data || data === '[DONE]') return;

  let payload;
  try {
    payload = JSON.parse(data);
  } catch {
    return;
  }

  const deltas = payload?.choices?.[0]?.delta?.tool_calls;
  if (!Array.isArray(deltas)) return;

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

function commitSseToolCalls(callsByIndex, cache = toolCallCache) {
  for (const call of callsByIndex.values()) {
    const normalized = normalizeToolCall(call);
    if (normalized) cache.set(normalized.id, normalized);
  }
}

function cacheJsonToolCalls(buffer) {
  try {
    cacheToolCallsFromJson(JSON.parse(buffer.toString('utf8')));
  } catch {
    // Upstream errors can contain non-JSON bodies. They pass through unchanged.
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

export function resolveUpstreamUrl(requestTarget, upstream) {
  if (
    typeof requestTarget !== 'string' ||
    !requestTarget.startsWith('/') ||
    requestTarget.startsWith('//')
  ) {
    throw new HttpError(400, 'invalid request target');
  }

  const upstreamUrl = new URL(upstream);
  const resolved = new URL(requestTarget, upstreamUrl);
  if (resolved.origin !== upstreamUrl.origin) {
    throw new HttpError(400, 'request target must stay on the configured upstream');
  }
  return resolved;
}

async function readBody(request, maxRequestBytes) {
  const chunks = [];
  let size = 0;

  for await (const chunk of request) {
    size += chunk.length;
    if (size > maxRequestBytes) {
      throw new HttpError(413, 'request body too large');
    }
    chunks.push(chunk);
  }

  return Buffer.concat(chunks);
}

function responseHeaders(headers) {
  const forwarded = {};
  for (const [name, value] of headers.entries()) {
    if (['content-length', 'content-encoding', 'transfer-encoding'].includes(name)) {
      continue;
    }
    forwarded[name] = value;
  }
  return forwarded;
}

export async function writeWithBackpressure(response, chunk) {
  if (response.destroyed) return false;
  if (response.write(chunk)) return true;

  return await new Promise((resolve) => {
    const finish = (writable) => {
      response.off('drain', onDrain);
      response.off('close', onClose);
      response.off('error', onClose);
      resolve(writable);
    };
    const onDrain = () => finish(!response.destroyed);
    const onClose = () => finish(false);

    response.once('drain', onDrain);
    response.once('close', onClose);
    response.once('error', onClose);
  });
}

async function forwardUpstreamResponse(upstreamResponse, response) {
  const contentType = upstreamResponse.headers.get('content-type') ?? '';
  const isSse = contentType.includes('text/event-stream');
  const isJson = contentType.includes('application/json');
  const callsByIndex = new Map();
  const decoder = isSse ? new TextDecoder() : null;
  let sseRemainder = '';
  let jsonCapture = [];
  let jsonCaptureSize = 0;
  let captureJson = isJson;

  response.writeHead(upstreamResponse.status, responseHeaders(upstreamResponse.headers));
  if (!upstreamResponse.body) {
    response.end();
    return;
  }

  for await (const chunk of upstreamResponse.body) {
    const buffer = Buffer.from(chunk);

    if (isSse) {
      sseRemainder += decoder.decode(buffer, { stream: true });
      const lines = sseRemainder.split(/\r?\n/);
      sseRemainder = lines.pop() ?? '';
      for (const line of lines) collectSseToolCalls(line, callsByIndex);
    } else if (captureJson) {
      jsonCaptureSize += buffer.length;
      if (jsonCaptureSize <= MAX_JSON_CAPTURE_BYTES) {
        jsonCapture.push(buffer);
      } else {
        jsonCapture = [];
        captureJson = false;
      }
    }

    if (!(await writeWithBackpressure(response, buffer))) {
      await upstreamResponse.body.cancel();
      return;
    }
  }

  if (isSse) {
    sseRemainder += decoder.decode();
    for (const line of sseRemainder.split(/\r?\n/)) {
      collectSseToolCalls(line, callsByIndex);
    }
    commitSseToolCalls(callsByIndex);
  } else if (captureJson) {
    cacheJsonToolCalls(Buffer.concat(jsonCapture));
  }

  response.end();
}

export function startServer({
  port = Number(process.env.PORT || DEFAULT_PORT),
  upstream = process.env.OLLAMA_BASE_URL || DEFAULT_UPSTREAM,
  reasoningEffort = process.env.REASONING_EFFORT || DEFAULT_REASONING_EFFORT,
  maxRequestBytes = MAX_REQUEST_BYTES,
} = {}) {
  const server = http.createServer(async (request, response) => {
    if (request.url === '/healthz') {
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end('{"status":"ok"}');
      return;
    }

    try {
      const upstreamUrl = resolveUpstreamUrl(request.url, upstream);
      const rawBody = await readBody(request, maxRequestBytes);
      let body = rawBody;

      if (
        request.method === 'POST' &&
        upstreamUrl.pathname.endsWith('/v1/chat/completions') &&
        rawBody.length > 0
      ) {
        let payload;
        try {
          payload = JSON.parse(rawBody.toString('utf8'));
        } catch {
          payload = null;
        }

        if (payload && Array.isArray(payload.messages)) {
          const sanitized = sanitizeMessages(payload.messages);
          const flattened = flattenToolHistory(sanitized.messages);
          payload.messages = flattened.messages;
          payload.reasoning_effort = reasoningEffort;
          body = Buffer.from(JSON.stringify(payload));

          console.log(
            JSON.stringify({
              path: upstreamUrl.pathname,
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
      }

      const abortController = new AbortController();
      request.once('aborted', () => abortController.abort());
      response.once('close', () => {
        if (!response.writableEnded) abortController.abort();
      });

      const upstreamResponse = await fetch(upstreamUrl, {
        method: request.method,
        headers: forwardHeaders(request.headers),
        body: ['GET', 'HEAD'].includes(request.method ?? 'GET') ? undefined : body,
        signal: abortController.signal,
      });
      await forwardUpstreamResponse(upstreamResponse, response);
    } catch (error) {
      if (response.headersSent) {
        response.destroy(error instanceof Error ? error : undefined);
        return;
      }

      const statusCode = error instanceof HttpError ? error.statusCode : 502;
      if (statusCode >= 500) console.error(error);
      response.writeHead(statusCode, { 'content-type': 'application/json' });
      response.end(
        JSON.stringify({
          error: {
            message: error instanceof Error ? error.message : String(error),
            type: statusCode >= 500 ? 'adapter_error' : 'invalid_request_error',
          },
        }),
      );
    }
  });

  server.listen(port, '0.0.0.0', () => {
    const address = server.address();
    const listeningPort = typeof address === 'object' && address ? address.port : port;
    console.log(`ollama-adapter listening on ${listeningPort}, upstream ${upstream}`);
  });

  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  startServer();
}
