import { test } from 'node:test';
import assert from 'node:assert/strict';
import { structuredResponse } from '../src/provider.ts';

const result = { reply: 'Orientação com fonte aprovada.', tool: '', arguments: '{}' };
const accepted = () => Response.json({ choices: [{ message: { content: JSON.stringify(result) } }],
  usage: { prompt_tokens: 140, completion_tokens: 10, total_tokens: 150 } });
const limited = (retryAfter?: string, code = 'rate_limit_exceeded') => Response.json({ error: { code } },
  { status: 429, headers: retryAfter === undefined ? {} : { 'retry-after': retryAfter } });
const options = { url: 'https://api.groq.com/openai/v1/chat/completions', apiKey: 'test-only', retryInvalid: true,
  body: { model: 'test-model', messages: [{ role: 'user', content: 'Consultar conhecimento aprovado' }] },
  validate: (value: any) => value };

test('Groq honors Retry-After once, repeats only the rejected inference and records only confirmed usage', async t => {
  const requests: string[] = [];
  const began = Date.now();
  t.mock.method(globalThis, 'fetch', async (_url, init) => {
    requests.push(String(init.body));
    return requests.length === 1 ? limited('0.034') : accepted();
  });
  const response = await structuredResponse(options);
  assert.equal(requests.length, 2);
  assert.equal(requests[0], requests[1]);
  assert.ok(Date.now() - began >= 25);
  assert.deepEqual(response.result, result);
  assert.equal(response.usage.total_tokens, 150);
  assert.equal(response.usageEstimated, false);
});

test('a second rate rejection is returned without an unbounded retry loop', async t => {
  const fetch = t.mock.method(globalThis, 'fetch', async () => limited('0'));
  await assert.rejects(structuredResponse(options), { code: 'provider_rate_limited' });
  assert.equal(fetch.mock.callCount(), 2);
});

for (const header of [undefined, '-1', 'tomorrow', 'Infinity', '60']) {
  test('missing, invalid or out-of-deadline Retry-After remains a controlled rejection: ' + header, async t => {
    const fetch = t.mock.method(globalThis, 'fetch', async () => limited(header));
    await assert.rejects(structuredResponse({ ...options, timeoutMs: 100 }), { code: 'provider_rate_limited' });
    assert.equal(fetch.mock.callCount(), 1);
  });
}

for (const url of ['https://api.openai.com/v1/chat/completions', 'https://api.groq.com.invalid/chat/completions']) {
  test('the Groq recovery does not change another provider: ' + url, async t => {
    const fetch = t.mock.method(globalThis, 'fetch', async () => limited('0'));
    await assert.rejects(structuredResponse({ ...options, url }), { code: 'provider_rate_limited' });
    assert.equal(fetch.mock.callCount(), 1);
  });
}

for (const code of ['insufficient_quota', 'billing_hard_limit_reached', 'blocked_api_access']) {
  test('financial quota rejection is not retried: ' + code, async t => {
    const fetch = t.mock.method(globalThis, 'fetch', async () => limited('0', code));
    await assert.rejects(structuredResponse(options), { code: 'provider_quota_exceeded' });
    assert.equal(fetch.mock.callCount(), 1);
  });
}

test('cancelling during the provider wait stops the retry before another request', async t => {
  const cancellation = new AbortController();
  const fetch = t.mock.method(globalThis, 'fetch', async () => {
    setTimeout(() => cancellation.abort(), 10);
    return limited('0.1');
  });
  await assert.rejects(structuredResponse({ ...options, signal: cancellation.signal }), { code: 'request_cancelled' });
  assert.equal(fetch.mock.callCount(), 1);
});

test('a transport failure after the rejected request remains uncertain and is not replayed', async t => {
  let calls = 0;
  t.mock.method(globalThis, 'fetch', async () => {
    if (++calls === 1) return limited('0');
    throw new TypeError('transport unavailable');
  });
  await assert.rejects(structuredResponse(options), (error: any) => {
    assert.equal(error.code, 'provider_transport_error');
    assert.equal(error.accounting, undefined);
    return true;
  });
  assert.equal(calls, 2);
});

test('a rate rejection does not consume the structured-output repair attempt or fabricate tokens', async t => {
  let calls = 0;
  t.mock.method(globalThis, 'fetch', async () => {
    calls += 1;
    if (calls === 1) return limited('0');
    return accepted();
  });
  let validations = 0;
  const { NicoError } = await import('../src/errors.ts');
  const response = await structuredResponse({ ...options, validate: (value: any) => {
    if (++validations === 1) throw new NicoError('tool_arguments_invalid');
    return value;
  } });
  assert.equal(calls, 3);
  assert.equal(validations, 2);
  assert.equal(response.usage.total_tokens, 300);
  assert.equal(response.usageEstimated, false);
});

test('successful Groq recovery does not grant another rate retry during JSON repair', async t => {
  let calls = 0;
  t.mock.method(globalThis, 'fetch', async () => ++calls === 2 ? accepted() : limited('0'));
  const { NicoError } = await import('../src/errors.ts');
  await assert.rejects(structuredResponse({ ...options, validate: () => {
    throw new NicoError('provider_schema_invalid');
  } }), { code: 'provider_rate_limited' });
  assert.equal(calls, 3);
});
