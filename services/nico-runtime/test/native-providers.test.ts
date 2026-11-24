import { test } from 'node:test';
import assert from 'node:assert/strict';
import { structuredResponse } from '../src/provider.ts';
import { requestProvider } from '../src/provider-config.ts';

const body = { model: 'test-model', max_completion_tokens: 2000,
  response_format: { json_schema: { schema: { type: 'object', properties: { ok: { type: 'boolean' } }, required: ['ok'], additionalProperties: false } } },
  messages: [{ role: 'system', content: 'SYSTEM' }, { role: 'user', content: 'USER' }] };

test('Anthropic uses native headers, workspace, schema and complete real cache accounting', async t => {
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    assert.equal(url, 'https://api.anthropic.com/v1/messages');
    const headers = new Headers(options?.headers);
    assert.equal(headers.get('Authorization'), 'Bearer isolated-test-key');
    assert.equal(headers.get('anthropic-workspace-id'), 'wrkspc_testworkspace123');
    const request = JSON.parse(String(options?.body));
    assert.equal(request.system, 'SYSTEM');
    assert.equal(request.messages.length, 1);
    assert.equal(request.output_config.format.schema.type, 'object');
    assert.equal(request.temperature, undefined);
    return Response.json({ content: [{ type: 'text', text: '{"ok":true}' }],
      usage: { input_tokens: 10, cache_creation_input_tokens: 20, cache_read_input_tokens: 30, output_tokens: 5 } });
  });
  const result = await structuredResponse({ url: 'https://api.anthropic.com/v1/chat/completions', apiKey: 'isolated-test-key',
    providerType: 'anthropic', workspaceId: 'wrkspc_testworkspace123', body, retryInvalid: false, validate: value => value });
  assert.deepEqual(result.usage, { input_tokens: 60, output_tokens: 5, total_tokens: 65 });
  assert.equal(result.usageEstimated, false);
});

test('Gemini uses header authentication and counts returned thinking tokens without double counting cache', async t => {
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    assert.equal(url, 'https://generativelanguage.googleapis.com/v1beta/models/test-model:generateContent');
    assert.equal(new Headers(options?.headers).get('x-goog-api-key'), 'isolated-test-key');
    assert.ok(!String(url).includes('key='));
    const request = JSON.parse(String(options?.body));
    assert.equal(request.generationConfig.responseMimeType, 'application/json');
    return Response.json({ candidates: [{ content: { parts: [{ thought: true, text: 'private' }, { text: '{"ok":true}' }] } }],
      usageMetadata: { promptTokenCount: 100, cachedContentTokenCount: 80, thoughtsTokenCount: 20, candidatesTokenCount: 5, totalTokenCount: 125 } });
  });
  const result = await structuredResponse({ url: 'https://generativelanguage.googleapis.com/v1beta/chat/completions',
    apiKey: 'isolated-test-key', providerType: 'google_gemini', body, retryInvalid: false, validate: value => value });
  assert.deepEqual(result.usage, { input_tokens: 100, output_tokens: 25, total_tokens: 125 });
  assert.deepEqual(result.result, { ok: true });
});

test('native usage cannot be fabricated when the provider omits its receipt', async t => {
  t.mock.method(globalThis, 'fetch', async () => Response.json({ content: [{ type: 'text', text: '{"ok":true}' }] }));
  await assert.rejects(structuredResponse({ url: 'https://api.anthropic.com/v1/chat/completions', apiKey: 'test',
    providerType: 'anthropic', body, retryInvalid: false, validate: value => value }), { code: 'provider_usage_invalid' });
});

test('native credentials are rejected before transport when protocol and host disagree', () => {
  const previous = process.env.NICO_PROVIDER_ALLOWED_HOSTS;
  process.env.NICO_PROVIDER_ALLOWED_HOSTS = 'api.anthropic.com,api.groq.com,generativelanguage.googleapis.com';
  try {
    assert.throws(() => requestProvider({ provider_type: 'anthropic', api_key: 'test', model: 'test', base_url: 'https://api.groq.com/openai/v1' }), { code: 'invalid_configuration' });
    assert.equal(requestProvider({ provider_type: 'anthropic', api_key: 'test', model: 'test', base_url: 'https://api.anthropic.com/v1', workspace_id: 'wrkspc_testworkspace123' })?.workspaceId, 'wrkspc_testworkspace123');
  } finally {
    if (previous === undefined) delete process.env.NICO_PROVIDER_ALLOWED_HOSTS;
    else process.env.NICO_PROVIDER_ALLOWED_HOSTS = previous;
  }
});
