// TLS termination and fault barrier in front of the REAL Broker ingress.
// It forwards exact bytes/HMAC; it never implements service.ingest or a fake receiver.
import https from 'node:https';
import http from 'node:http';
import { readFile, appendFile } from 'node:fs/promises';
import { join } from 'node:path';
import { createHash, timingSafeEqual } from 'node:crypto';
import { directory, origin, settings, readJson, openTenantPool, custodyCounts } from './broker_https_broker.mjs';

const ca = await readFile(join(directory, 'ca.pem'));
if (process.argv[2] === 'control') {
  const operation = process.argv[3], key = process.argv[4] ?? 'a';
  if (!['arm', 'evidence', 'health', 'ready'].includes(operation) || !['a', 'b'].includes(key)) throw new Error('INVALID_PROXY_CONTROL');
  const url = new URL(`/_lab/${operation}/${key}`, origin);
  const result = await new Promise((resolve, reject) => {
    const request = https.request(url, { method: operation === 'arm' ? 'POST' : 'GET', ca, rejectUnauthorized: true,
      headers: { 'X-Lab-Control': settings.control_token } }, response => {
      const chunks = [];
      response.on('data', chunk => chunks.push(chunk));
      response.on('end', () => response.statusCode === 200 ? resolve(JSON.parse(Buffer.concat(chunks).toString())) : reject(new Error('PROXY_CONTROL_REJECTED')));
    });
    request.on('error', reject); request.end();
  });
  console.log(JSON.stringify(result));
  process.exit(0);
}
if (process.argv[2] !== 'serve') throw new Error('UNKNOWN_PROXY_MODE');
const manifest = await readJson('manifest.json'), pool = await openTenantPool();
const contexts = manifest.contexts;
if (contexts.length !== 2 || contexts.some(context => !Number.isInteger(context.message_id))) throw new Error('COMMITTED_CONTEXTS_REQUIRED');
const wire = [], kills = new Map();
let armed = null;
const token = Buffer.from(settings.control_token);
const authorized = request => {
  const given = Buffer.from(String(request.headers['x-lab-control'] ?? ''));
  return given.length === token.length && timingSafeEqual(given, token);
};
const log = async value => appendFile(join(directory, 'wire.jsonl'), JSON.stringify(value) + '\n', { mode: 0o600 });
const json = (response, status, value) => { response.writeHead(status, { 'Content-Type': 'application/json' }); response.end(JSON.stringify(value)); };
const counts = async context => custodyCounts(pool, context, contexts.find(other => other.key !== context.key).organization_id);
async function control(request, response, url) {
  if (!authorized(request)) return json(response, 403, { code: 'LAB_CONTROL_REQUIRED' });
  const [, , action, key] = url.pathname.split('/'), context = contexts.find(item => item.key === key);
  if (!context) return json(response, 404, { code: 'UNKNOWN_LAB_CONTEXT' });
  if (action === 'arm' && request.method === 'POST') {
    if (key !== 'a' || armed !== null || kills.size) return json(response, 409, { code: 'BARRIER_ALREADY_USED' });
    armed = key; return json(response, 200, { armed: key, run_id: manifest.run_id });
  }
  if (action === 'kill') return json(response, 200, kills.get(key) ?? { kill: false });
  if (action === 'ready') return json(response, 200, { fixture_proxy: true, verify_peer_required: true });
  if (action === 'health') {
    const status = await new Promise(resolve => {
      const probe = http.get('http://broker-https-api:8080/health', value => { value.resume(); value.on('end', () => resolve(value.statusCode)); });
      probe.on('error', () => resolve(503)); probe.setTimeout(2000, () => probe.destroy());
    });
    return json(response, status === 200 ? 200 : 503, { real_broker_health_status: status });
  }
  if (action === 'evidence') return json(response, 200, { counts: await counts(context),
    wire_requests: wire.filter(item => item.key === key && !item.negative_probe),
    negative_requests: wire.filter(item => item.negative_probe), physical_transport_worker_started: false });
  return json(response, 404, { code: 'UNKNOWN_LAB_CONTROL' });
}
async function handle(request, response) {
  const url = new URL(request.url, origin);
  if (url.pathname.startsWith('/_lab/')) return control(request, response, url);
  const match = /^\/v1\/integrations\/chatwoot\/([a-f0-9-]{36})\/events$/.exec(url.pathname);
  if (url.pathname !== '/health' && (!match || request.method !== 'POST')) return json(response, 404, { code: 'FIXTURE_ROUTE_ONLY' });
  const chunks = []; let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 1_048_576) return json(response, 413, { code: 'FIXTURE_BODY_LIMIT' });
    chunks.push(chunk);
  }
  const body = Buffer.concat(chunks), context = match ? contexts.find(item => item.integration_id === match[1]) : null;
  if (match && !context) return json(response, 404, { code: 'FIXTURE_INTEGRATION_ONLY' });
  const entry = context ? { key: context.key, integration_id: context.integration_id,
    delivery_id: String(request.headers['x-chatwoot-delivery'] ?? ''), body_sha256: createHash('sha256').update(body).digest('hex'),
    negative_probe: request.headers['x-lab-negative-probe'] === manifest.run_id && authorized(request),
    upstream_unavailable: false, upstream_status: null, ack_withheld_after_commit: false, client_disconnected_before_ack: false } : null;
  if (entry) wire.push(entry);
  const forwarded = Object.fromEntries(['content-type', 'x-chatwoot-delivery', 'x-chatwoot-timestamp', 'x-chatwoot-signature']
    .filter(name => request.headers[name] !== undefined).map(name => [name, request.headers[name]]));
  forwarded['content-length'] = body.length;
  let upstream;
  try {
    upstream = await new Promise((resolve, reject) => {
      const outgoing = http.request({ hostname: 'broker-https-api', port: 8080, path: url.pathname,
        method: request.method, headers: forwarded, timeout: 10_000 }, incoming => {
        const values = []; incoming.on('data', chunk => values.push(chunk));
        incoming.on('end', () => resolve({ status: incoming.statusCode, headers: incoming.headers, body: Buffer.concat(values) }));
      });
      outgoing.on('error', reject); outgoing.on('timeout', () => outgoing.destroy(new Error('UPSTREAM_TIMEOUT'))); outgoing.end(body);
    });
  } catch (error) {
    if (entry) { entry.upstream_unavailable = ['ECONNREFUSED', 'ENOTFOUND', 'EAI_AGAIN'].includes(error.code); entry.upstream_error = error.code ?? 'UPSTREAM_ERROR'; await log(entry); }
    return json(response, 503, { code: 'LAB_REAL_BROKER_UNAVAILABLE' });
  }
  if (entry) entry.upstream_status = upstream.status;
  if (entry && !entry.negative_probe && armed === context.key && upstream.status === 200) {
    const committed = await counts(context);
    if (committed.observations !== 1 || committed.reply_jobs !== 1 || committed.cross_tenant_observations !== 0) {
      throw new Error('REAL_BROKER_COMMIT_BARRIER_MISSING');
    }
    if (entry.delivery_id !== context.delivery_id || entry.body_sha256 !== context.body_sha256) throw new Error('COMMIT_DELIVERY_LINEAGE_CHANGED');
    entry.ack_withheld_after_commit = true;
    kills.set(context.key, { kill: true, run_id: manifest.run_id, delivery_id: context.delivery_id,
      upstream_status: upstream.status, counts: committed });
    armed = null;
    response.on('close', () => {
      entry.client_disconnected_before_ack = !response.headersSent;
      void log({ ...entry, phase: 'client_disconnected' });
    });
    await log({ ...entry, phase: 'receiver_committed_ack_withheld' });
    // The request remains unanswered. The real Sidekiq process observes the SQL-confirmed barrier and receives SIGKILL.
    const timer = setTimeout(() => response.destroy(), 30_000);
    response.on('close', () => clearTimeout(timer));
    return;
  }
  if (entry) await log(entry);
  response.writeHead(upstream.status, { 'Content-Type': upstream.headers['content-type'] ?? 'application/json' });
  response.end(upstream.body);
}
const key = await readFile(join(directory, 'server-key.pem'));
const good = https.createServer({ key, cert: await readFile(join(directory, 'server.pem')) }, (request, response) => {
  void handle(request, response).catch(error => { console.error(JSON.stringify({ fixture_proxy_error: error.name })); if (!response.headersSent) json(response, 503, { code: 'LAB_BARRIER_ERROR' }); else response.destroy(); });
});
const wrongHostname = https.createServer({ key, cert: await readFile(join(directory, 'wrong-host.pem')) }, (request, response) => {
  void handle(request, response).catch(() => response.destroy());
});
await Promise.all([new Promise(resolve => good.listen(443, '0.0.0.0', resolve)), new Promise(resolve => wrongHostname.listen(444, '0.0.0.0', resolve))]);
console.log(JSON.stringify({ fixture_tls_proxy: true, real_upstream: 'broker-https-api:8080', no_public_ports: true, physical_worker_started: false }));
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, async () => { good.closeAllConnections(); wrongHostname.closeAllConnections(); good.close(); wrongHostname.close(); await pool.end(); process.exit(0); });
