import { createServer } from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { errorResponse } from './errors.ts';
import { createEngine } from './engine.ts';
import { validateInput } from './contract.ts';
import { validateOperation } from './operations.ts';
import { validateAudio } from './transcription.ts';
import { requestProvider } from './provider-config.ts';
import { validateSentimentInput } from './sentiment.ts';

const token = process.env.NICO_SERVICE_TOKEN;
if (!token || token.length < 32) throw new Error('NICO_SERVICE_TOKEN must have at least 32 characters');
const accounts = new Set((process.env.NICO_ALLOWED_ACCOUNTS || '').split(',').filter(id => /^[1-9][0-9]*$/.test(id)));
const allAccounts = process.env.NICO_ALLOWED_ACCOUNTS === '*';
if (!accounts.size && !allAccounts) throw new Error('NICO_ALLOWED_ACCOUNTS is required');
const mode = process.env.NICO_MODE;
if (mode !== 'fixture' && mode !== 'provider') throw new Error('NICO_MODE must be fixture or provider');
const engine = await createEngine({ mode, dataDir: process.env.NICO_PGLITE_DATA_DIR, postgresUrl: process.env.NICO_DATABASE_URL });

const server = createServer(async (req, res) => {
  const cancellation = new AbortController();
  res.on('close', () => { if (!res.writableEnded) cancellation.abort(); });
  const send = (status: number, body: unknown) => { if (res.destroyed || res.writableEnded) return; res.writeHead(status, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(body)); };
  const reject = (status: number, code: string) => {
    console.error(JSON.stringify({ event: 'nico_request_failed', code }));
    return send(status, { error: code });
  };
  if (req.url === '/health' && req.method === 'GET') return send(200, { ready: true, mode, provider_verified: false });
  const received = Buffer.from(req.headers.authorization || '');
  const expected = Buffer.from(`Bearer ${token}`);
  if (received.length !== expected.length || !timingSafeEqual(received, expected)) return reject(401, 'unauthorized');
  if (!['/v1/analyze', '/v1/operate', '/v1/transcribe', '/v1/sentiment'].includes(req.url || '') || req.method !== 'POST') return send(404, { error: 'not_found' });
  if (!req.headers['content-type']?.startsWith('application/json')) return send(415, { error: 'json_required' });
  try {
    let size = 0;
    const chunks: Buffer[] = [];
    for await (const chunk of req) {
      size += chunk.length;
      if (size > (req.url === '/v1/transcribe' ? 5600000 : 262144)) return send(413, { error: 'body_too_large' });
      chunks.push(chunk);
    }
    let input;
    let provider;
    try {
      const { provider: configuration, ...raw } = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      input = (req.url === '/v1/transcribe' ? validateAudio : req.url === '/v1/operate' ? validateOperation
        : req.url === '/v1/sentiment' ? validateSentimentInput : validateInput)(raw);
      provider = requestProvider(configuration);
    }
    catch { return send(422, { error: 'invalid_input' }); }
    if (!allAccounts && !accounts.has(String(input.account_id))) return reject(403, 'account_not_configured');
    if (mode === 'provider' && !provider) return reject(422, 'account_ai_not_configured');
    const audio = { ...input };
    delete audio.bytes;
    const result = req.url === '/v1/transcribe' ? await engine.transcribe(audio, cancellation.signal, provider)
      : req.url === '/v1/operate' ? await engine.operate(input as any, cancellation.signal, provider)
      : req.url === '/v1/sentiment' ? await engine.sentiment(input as any, cancellation.signal, provider)
      : await engine.analyze(input as any, cancellation.signal, provider);
    send(200, { ...result, request_id: input.request_id, account_id: input.account_id });
  } catch (error) {
    const failure = errorResponse(error, req.url || '');
    console.error(JSON.stringify(failure.log));
    send(failure.status, failure.body);
  }
});
server.requestTimeout = 10000;
server.headersTimeout = 10000;
server.listen(Number(process.env.PORT || 3108), '0.0.0.0');
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.close(() => { void engine.close().finally(() => process.exit(0)); }));
