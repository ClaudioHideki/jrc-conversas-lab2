import { test } from 'node:test';
import assert from 'node:assert/strict';
import { requestProvider } from '../src/provider-config.ts';
import { structuredResponse } from '../src/provider.ts';

test('request provider configurations never share credentials or models', () => {
  const one = requestProvider({ api_key: 'test-company-one', model: 'model-one', base_url: 'https://api.openai.com/v1' });
  const two = requestProvider({ api_key: 'test-company-two', model: 'model-two', base_url: 'https://api.openai.com/v1' });
  assert.equal(one?.apiKey, 'test-company-one');
  assert.equal(two?.apiKey, 'test-company-two');
  assert.equal(one?.model, 'model-one');
  assert.equal(requestProvider(undefined), undefined);
});

test('rejects credentials for unapproved URLs and malformed envelopes', () => {
  for (const base_url of ['http://api.openai.com/v1', 'https://localhost/v1', 'https://api.openai.com.attacker.invalid/v1',
    'https://user:password@api.openai.com/v1', 'https://api.openai.com/v1?token=test', 'https://api.openai.com:8443/v1']) {
    assert.throws(() => requestProvider({ api_key: 'test', model: 'test', base_url }), { code: 'invalid_configuration' });
  }
  assert.throws(() => requestProvider({ api_key: 'test\r\nheader', model: 'test', base_url: 'https://api.openai.com/v1' }));
});

test('distinguishes API quota from rate limit without exposing provider secrets', async t => {
  t.mock.method(globalThis, 'fetch', async () => Response.json({ error: { code: 'insufficient_quota', message: 'PRIVATE_PROVIDER_DETAIL' } }, { status: 429 }));
  await assert.rejects(structuredResponse({ url: 'https://api.openai.com/v1/chat/completions', apiKey: 'test',
    body: { messages: [] }, validate: value => value, retryInvalid: false }), error => {
    assert.equal((error as any).code, 'provider_quota_exceeded');
    assert.ok(!String(error).includes('PRIVATE_PROVIDER_DETAIL'));
    return true;
  });
});
