import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createEngine } from '../src/engine.ts';

const input = { request_id: 'a56905c4-9a03-4c21-a886-b5d18a3e4c57', account_id: 1, kind: 'operator' as const, message: 'Crie um contato', history: [], context: {} };
test('concurrent tenant operations keep their own key, model and prompt scope', { timeout: 60000 }, async t => {
  const dir = await mkdtemp(join(tmpdir(), 'nico-tenant-isolation-'));
  const engine = await createEngine({ mode: 'provider', dataDir: dir });
  const seen: Array<{ account: number; model: string; authorization: string }> = [];
  let ready!: () => void;
  const bothStarted = new Promise<void>(resolve => { ready = resolve; });
  t.mock.method(globalThis, 'fetch', async (_url, options: any) => {
    const body = JSON.parse(options.body);
    const context = JSON.parse(body.messages[1].content);
    assert.ok(!options.body.includes('test-company-'));
    seen.push({ account: context.account_id, model: body.model, authorization: options.headers.Authorization });
    if (seen.length === 2) ready();
    await bothStarted;
    return Response.json({ choices: [{ message: { content: JSON.stringify({ reply: 'Sem ação', tool: '', arguments: '{}' }) } }],
      usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 } });
  });
  try {
    await Promise.all([1, 2].map(account => engine.operate({ ...input, account_id: account }, undefined,
      { apiKey: `test-company-${account}`, model: `model-${account}`, baseUrl: 'https://api.openai.com/v1' })));
    assert.deepEqual(seen.sort((a, b) => a.account - b.account), [1, 2].map(account =>
      ({ account, model: `model-${account}`, authorization: `Bearer test-company-${account}` })));
  } finally {
    await engine.close();
    await rm(dir, { recursive: true, force: true });
  }
});
