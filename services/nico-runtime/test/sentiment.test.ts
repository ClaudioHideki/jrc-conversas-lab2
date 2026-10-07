import { test } from 'node:test';
import assert from 'node:assert/strict';
import { analyzeSentiment, validateSentimentInput, validateSentimentReport } from '../src/sentiment.ts';

const input = { request_id: 'a56905c4-9a03-4c21-a886-b5d18a3e4c57', account_id: 1, conversation_id: 45,
  channel: 'Channel::Whatsapp', messages: [{ id: 11, role: 'customer', content: 'Obrigado pelo atendimento' }] };
const report = { summary: 'Cliente satisfeito na amostra.', customer_sentiment: 'positive', agent_sentiment: 'insufficient_data',
  quality_score: null, risks: [], recommendations: [], evidence: [{ message_id: 11, observation: 'Agradecimento' }], limitations: 'Uma mensagem pública.' };

test('requires bounded public message projection with an exact account and conversation', () => {
  assert.deepEqual(validateSentimentInput(input), input);
  assert.throws(() => validateSentimentInput({ ...input, account_id: '1' }));
  assert.throws(() => validateSentimentInput({ ...input, messages: [{ ...input.messages[0], private: true }] }));
  assert.throws(() => validateSentimentInput({ ...input, messages: [input.messages[0], input.messages[0]] }));
});

test('rejects evidence from messages outside the supplied conversation', () => {
  assert.deepEqual(validateSentimentReport(report, input), report);
  assert.throws(() => validateSentimentReport({ ...report, evidence: [{ message_id: 999, observation: 'invented' }] }, input));
  assert.throws(() => validateSentimentReport({ ...report, quality_score: 101 }, input));
  assert.throws(() => validateSentimentReport({ ...report, quality_score: 90 }, input));
  assert.throws(() => validateSentimentReport({ ...report, agent_sentiment: 'positive' }, input));
  assert.throws(() => validateSentimentReport({ ...report, evidence: [] }, input));
  assert.throws(() => validateSentimentReport(report, { ...input, messages: [{ ...input.messages[0], role: 'bot' }] }));
  const unknown = { ...input, messages: [{ ...input.messages[0], role: 'unknown' }] };
  assert.deepEqual(validateSentimentInput(unknown), unknown);
  assert.throws(() => validateSentimentReport({ ...report, customer_sentiment: 'insufficient_data', quality_score: 90 }, unknown));
});

test('uses the selected tenant model and never includes its credential in the prompt', async t => {
  t.mock.method(globalThis, 'fetch', async (_url, init: any) => {
    const body = JSON.parse(init.body);
    assert.equal(body.model, 'account-one-model');
    assert.equal(init.headers.Authorization, 'Bearer test-account-one-key');
    assert.ok(!init.body.includes('test-account-one-key'));
    return Response.json({ choices: [{ message: { content: JSON.stringify(report) } }],
      usage: { prompt_tokens: 20, completion_tokens: 10, total_tokens: 30 } });
  });
  const result = await analyzeSentiment(input, { apiKey: 'test-account-one-key', model: 'account-one-model', baseUrl: 'https://api.openai.com/v1' });
  assert.deepEqual(result.report, report);
  assert.equal(result.usage.total_tokens, 30);
});
