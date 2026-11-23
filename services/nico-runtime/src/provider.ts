import { setTimeout as delay } from 'node:timers/promises';
import { NicoError, type ProviderObservation } from './errors.ts';

const LIMIT_HEADERS = ['x-ratelimit-limit-requests', 'x-ratelimit-limit-tokens',
  'x-ratelimit-remaining-requests', 'x-ratelimit-remaining-tokens',
  'x-ratelimit-reset-requests', 'x-ratelimit-reset-tokens', 'retry-after'];

function observation(response: Response): ProviderObservation {
  const headers = Object.fromEntries(LIMIT_HEADERS.flatMap(key => {
    const value = response.headers.get(key);
    return value && /^[a-z0-9 .-]{1,80}$/i.test(value) ? [[key, value]] : [];
  }));
  return { http_status: response.status, headers };
}

export type Usage = { input_tokens: number; output_tokens: number; total_tokens: number };
const INVALID_OUTPUT = new Set(['provider_outer_json_invalid', 'tool_arguments_invalid', 'provider_schema_invalid']);
const REPAIR_INSTRUCTION = 'A resposta estruturada anterior era inválida. Gere novamente a resposta completa no schema exigido. '
  + 'arguments deve ser uma string que represente um objeto JSON válido, nunca array, null ou valor primitivo. '
  + 'Não corrija nem invente IDs, telefones, valores, datas ou destinatários. Use o mesmo contexto original. Nenhuma ferramenta foi executada nesta tentativa.';

async function readJson(response: Response): Promise<any> {
  const failure = response.status === 401 ? 'provider_unauthorized' : response.status === 403 ? 'provider_forbidden'
    : response.status === 429 ? 'provider_rate_limited' : 'provider_unavailable';
  if (!response.body) throw new NicoError(response.ok ? 'provider_outer_json_invalid' : failure);
  const reader = response.body.getReader();
  const parts: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 131072) throw new NicoError('provider_schema_invalid');
      parts.push(value);
    }
    let payload;
    try { payload = JSON.parse(Buffer.concat(parts).toString('utf8')); }
    catch { throw new NicoError(response.ok ? 'provider_outer_json_invalid' : failure); }
    if (!response.ok) {
      const quota = ['insufficient_quota', 'billing_hard_limit_reached', 'blocked_api_access'].includes(payload?.error?.code);
      throw new NicoError([400, 402, 429].includes(response.status) && quota ? 'provider_quota_exceeded' : failure);
    }
    return payload;
  } finally { await reader.cancel().catch(() => {}); }
}

export async function structuredResponse<T>(options: {
  url: string; apiKey: string; body: Record<string, any>; validate: (value: unknown) => T;
  retryInvalid: boolean; signal?: AbortSignal; timeoutMs?: number;
}) {
  // A single deadline includes both requests and response-body reads.
  const timeoutMs = options.timeoutMs ?? 45000;
  const deadlineAt = Date.now() + timeoutMs;
  const deadline = AbortSignal.timeout(timeoutMs);
  const groq = new URL(options.url).hostname === 'api.groq.com';
  let retriedRateLimit = false;
  const signal = AbortSignal.any([deadline, ...(options.signal ? [options.signal] : [])]);
  const usage: Usage = { input_tokens: 0, output_tokens: 0, total_tokens: 0 };
  let usageEstimated = false;
  let providerObservation: ProviderObservation | undefined;
  for (let attempt = 0; attempt < (options.retryInvalid ? 2 : 1); attempt++) {
    let accounted = false;
    try {
      signal.throwIfAborted();
      let body;
      while (true) {
        const response = await fetch(options.url, {
          method: 'POST', signal, redirect: 'error',
          headers: { Authorization: `Bearer ${options.apiKey}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ ...options.body, messages: [...options.body.messages,
            ...(attempt ? [{ role: 'system', content: REPAIR_INSTRUCTION }] : [])] }),
        });
        providerObservation = observation(response);
        try { body = await readJson(response); break; }
        catch (error) {
          const after = response.headers.get('retry-after') || '';
          const waitMs = /^\d+(?:\.\d+)?$/.test(after) ? Number(after) * 1000 : NaN;
          if (!groq || retriedRateLimit || !(error instanceof NicoError) || error.code !== 'provider_rate_limited'
            || !Number.isFinite(waitMs) || waitMs >= deadlineAt - Date.now()) throw error;
          // Only replay the inference explicitly rejected by Groq, within the original deadline.
          // No caller/tool execution is repeated, and rejected requests supply no usage receipt.
          retriedRateLimit = true;
          await delay(waitMs, undefined, { signal });
        }
      }
      signal.throwIfAborted();
      const measured = body?.usage;
      if (!measured || ![measured.prompt_tokens, measured.completion_tokens, measured.total_tokens]
        .every(n => Number.isSafeInteger(n) && n >= 0 && n <= 270000)
        || measured.prompt_tokens + measured.completion_tokens !== measured.total_tokens) throw new NicoError('provider_usage_invalid');
      usage.input_tokens += measured.prompt_tokens;
      usage.output_tokens += measured.completion_tokens;
      usage.total_tokens += measured.total_tokens;
      accounted = true;
      if (usage.total_tokens > 270000) throw new NicoError('provider_usage_invalid');
      const content = body.choices?.[0]?.message?.content;
      if (typeof content !== 'string') throw new NicoError('provider_schema_invalid');
      let parsed: unknown;
      try { parsed = JSON.parse(content); }
      catch { throw new NicoError('provider_outer_json_invalid'); }
      let result: T;
      try { result = options.validate(parsed); }
      catch (error) { throw error instanceof NicoError ? error : new NicoError('provider_schema_invalid'); }
      signal.throwIfAborted();
      return { result, usage, usageEstimated, providerObservation };
    } catch (error) {
      if (options.signal?.aborted) throw new NicoError('request_cancelled');
      if (deadline.aborted) throw new NicoError('provider_timeout');
      if (!(error instanceof NicoError)) throw new NicoError('provider_transport_error');
      error.providerObservation = providerObservation;
      if (!options.retryInvalid || attempt !== 0 || !INVALID_OUTPUT.has(error.code)) {
        // A later timeout/unmetered response must never turn an earlier partial receipt into complete accounting.
        if (accounted && INVALID_OUTPUT.has(error.code)) {
          const terminal = new NicoError(error.code, { version: 1, complete: true, attempts: attempt + 1, model: options.body.model,
            usage: { ...usage }, ...(usageEstimated ? { usage_estimated: true } : {}) });
          terminal.providerObservation = providerObservation;
          throw terminal;
        }
        throw error;
      }
      if (!accounted) {
        // Invalid HTTP JSON cannot supply usage. Charge a marked conservative estimate,
        // matching the Rails reservation, instead of silently dropping the first call.
        const inputBound = Buffer.byteLength(JSON.stringify(options.body.messages), 'utf8') + 10000;
        usage.input_tokens += inputBound;
        usage.output_tokens += 2000;
        usage.total_tokens += inputBound + 2000;
        usageEstimated = true;
      }
    }
  }
  throw new NicoError('provider_schema_invalid');
}
