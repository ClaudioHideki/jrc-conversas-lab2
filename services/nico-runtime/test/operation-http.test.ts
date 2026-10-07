import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

test('real engine/HTTP boundary retries before returning an action, reports controlled errors and redacts logs', { timeout: 60000 }, async () => {
  const dir = await mkdtemp(join(tmpdir(), 'nico-http-provider-'));
  const child = spawn(process.execPath, ['--import', './test/fixtures/provider-preload.mjs', 'src/server.ts'], {
    env: { ...process.env, PORT: '3196', NICO_MODE: 'provider', NICO_ALLOWED_ACCOUNTS: '1', NICO_MODEL: 'test-model',
      NICO_PROVIDER_API_KEY: 'PRIVATE_API_KEY', NICO_SERVICE_TOKEN: 'PRIVATE_SERVICE_TOKEN_MINIMUM_32_CHARS', NICO_PGLITE_DATA_DIR: dir }, stdio: 'pipe',
  });
  let output = '';
  child.stdout.on('data', chunk => { output += chunk.toString(); });
  child.stderr.on('data', chunk => { output += chunk.toString(); });
  const url = 'http://127.0.0.1:3196';
  const input = { request_id: 'a56905c4-9a03-4c21-a886-b5d18a3e4c57', account_id: 1, kind: 'operator', message: 'valid_second', history: [], context: {},
    provider: { api_key: 'PRIVATE_API_KEY', model: 'test-model', base_url: 'https://api.openai.com/v1' } };
  const headers = { authorization: 'Bearer PRIVATE_SERVICE_TOKEN_MINIMUM_32_CHARS', 'content-type': 'application/json' };
  try {
    let ready = false;
    for (let i = 0; i < 200; i++) {
      if (child.exitCode !== null) throw new Error('Provider fixture server exited');
      try { ready = (await fetch(`${url}/health`)).ok; } catch {}
      if (ready) break;
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    assert.ok(ready);
    const { provider: _provider, ...withoutProvider } = input;
    const missingProvider = await fetch(`${url}/v1/operate`, { method: 'POST', headers, body: JSON.stringify(withoutProvider) });
    assert.equal(missingProvider.status, 422);
    assert.equal((await missingProvider.json()).error, 'account_ai_not_configured');
    const valid = await fetch(`${url}/v1/operate`, { method: 'POST', headers, body: JSON.stringify(input) });
    assert.equal(valid.status, 200);
    const result = await valid.json();
    assert.equal(result.tool, 'count_contacts');
    assert.equal(result.arguments, '{}');
    assert.equal(result.usage.total_tokens, 30); // exactly two attempts through real elizaOS
    assert.equal(result.request_id, input.request_id);
    const invalid = await fetch(`${url}/v1/operate`, { method: 'POST', headers, body: JSON.stringify({ ...input, message: 'invalid_twice' }) });
    assert.equal(invalid.status, 502);
    assert.deepEqual(await invalid.json(), { error: 'tool_arguments_invalid' });
    const limited = await fetch(`${url}/v1/operate`, { method: 'POST', headers, body: JSON.stringify({ ...input, message: 'rate_limit' }) });
    assert.equal(limited.status, 429);
    assert.deepEqual(await limited.json(), { error: 'provider_rate_limited' });
    const denied = await fetch(`${url}/v1/operate`, { method: 'POST', headers, body: JSON.stringify({ ...input, account_id: 2 }) });
    assert.equal(denied.status, 403);
    assert.deepEqual(await denied.json(), { error: 'account_not_configured' });
  } finally {
    if (child.exitCode === null) { child.kill('SIGTERM'); await new Promise(resolve => child.once('exit', resolve)); }
    await rm(dir, { recursive: true, force: true });
  }
  assert.match(output, /"code":"tool_arguments_invalid"/);
  assert.match(output, /"code":"provider_rate_limited"/);
  for (const secret of ['PRIVATE_API_KEY', 'PRIVATE_SERVICE_TOKEN', 'PRIVATE_CONVERSATION', 'PRIVATE_PROVIDER_BODY', 'Authorization']) {
    assert.equal(output.includes(secret), false);
  }
});
