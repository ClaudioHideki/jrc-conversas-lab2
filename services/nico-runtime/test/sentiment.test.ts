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

const resource = { request_id: input.request_id, account_id: 1,
  source: { system: 'helpdesk', resource_type: 'Ticket', resource_id: '45' },
  messages: [{ id: 'Ticket/45', role: 'customer', content: 'Obrigado' },
    { id: 'ITILFollowup/45', role: 'operator', content: 'Resolvido' }] };
test('resource history preserves qualified source identifiers and rejects mixed contracts', () => {
  assert.deepEqual(validateSentimentInput(resource), resource);
  for (const invalid of [
    { ...resource, conversation_id: 45 },
    { ...resource, source: { ...resource.source, account_id: 2 } },
    { ...resource, source: { ...resource.source, resource_id: '0' } },
    { ...resource, messages: [{ ...resource.messages[0], id: 45 }] },
    { ...resource, messages: [resource.messages[0], resource.messages[0]] },
  ]) assert.throws(() => validateSentimentInput(invalid));
  const result = { ...report, agent_sentiment: 'positive', quality_score: 90,
    evidence: [{ message_id: 'ITILFollowup/45', observation: 'Solução informada' }] };
  assert.deepEqual(validateSentimentReport(result, resource), result);
  assert.throws(() => validateSentimentReport({ ...result, evidence: [{ message_id: 'Ticket/99', observation: 'Inventado' }] }, resource));
  assert.throws(() => validateSentimentReport({ ...result, evidence: [{ message_id: 45, observation: 'Ambíguo' }] }, resource));
});
test('resource inference uses string evidence schema and records actual provider usage', async t => {
  const result = { ...report, evidence: [{ message_id: 'Ticket/45', observation: 'Agradecimento' }] };
  t.mock.method(globalThis, 'fetch', async (_url, init: any) => {
    const body = JSON.parse(init.body);
    assert.equal(body.response_format.json_schema.schema.properties.evidence.items.properties.message_id.type, 'string');
    assert.deepEqual(JSON.parse(body.messages[1].content).source, resource.source);
    return Response.json({ choices: [{ message: { content: JSON.stringify(result) } }],
      usage: { prompt_tokens: 12, completion_tokens: 9, total_tokens: 21 } });
  });
  const response = await analyzeSentiment(resource, { apiKey: 'test', model: 'test', baseUrl: 'https://api.openai.com/v1' });
  assert.equal(response.usage.total_tokens, 21);
  assert.deepEqual(response.report.evidence, result.evidence);
});

test('generation cannot assign sentiment or quality to an unproven human author', async t => {
  const unknown = { ...resource, messages: resource.messages.map(message => ({ ...message, role: 'unknown' })) };
  const result = { ...report, customer_sentiment: 'insufficient_data', agent_sentiment: 'insufficient_data',
    quality_score: null, evidence: [{ message_id: 'Ticket/45', observation: 'Autoria não comprovada' }] };
  t.mock.method(globalThis, 'fetch', async (_url, init: any) => {
    const properties = JSON.parse(init.body).response_format.json_schema.schema.properties;
    assert.deepEqual(properties.customer_sentiment.enum, ['insufficient_data']);
    assert.deepEqual(properties.agent_sentiment.enum, ['insufficient_data']);
    assert.deepEqual(properties.quality_score, { type: 'null' });
    assert.deepEqual(properties.evidence.items.properties.message_id.enum, ['Ticket/45', 'ITILFollowup/45']);
    return Response.json({ choices: [{ message: { content: JSON.stringify(result) } }],
      usage: { prompt_tokens: 23, completion_tokens: 11, total_tokens: 34 } });
  });
  const response = await analyzeSentiment(unknown, { apiKey: 'test', model: 'test', baseUrl: 'https://api.groq.com/openai/v1' });
  assert.equal(response.usage.total_tokens, 34);
  assert.equal(response.report.quality_score, null);
});
