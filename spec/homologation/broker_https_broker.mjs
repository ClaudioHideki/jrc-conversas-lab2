// Shared real Broker/PG laboratory support. No service, transaction or fetch double.
import { readFile, writeFile, rename } from 'node:fs/promises';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';

export const directory = process.env.BROKER_HTTPS_DIRECTORY;
export const origin = 'https://broker-https-lab.test';
export const dist = '/app/apps/api/dist';
if (process.env.BROKER_HTTPS_LAB !== '1' || process.env.NODE_ENV !== 'test' || directory !== '/fixture') {
  throw new Error('EXPLICIT_HTTPS_FIXTURE_REQUIRED');
}
if (Number(process.versions.node.split('.')[0]) < 24) throw new Error('NODE_24_FIXTURE_REQUIRED');
const require = createRequire('/app/package.json');
export const { Pool } = require('pg');
export const settings = JSON.parse(await readFile(join(directory, 'settings.private.json'), 'utf8'));
if (settings.fixture_only !== true || !/^[a-f0-9-]{36}$/.test(settings.run_id)) throw new Error('INVALID_FIXTURE_SETTINGS');
export const brokerModule = relative => import(pathToFileURL(join(dist, relative)).href);
export const readJson = async name => JSON.parse(await readFile(join(directory, name), 'utf8'));
export async function writeJson(name, value) {
  if (!/^[a-z0-9_.-]+\.json$/.test(name)) throw new Error('INVALID_FIXTURE_FILENAME');
  const path = join(directory, name), temporary = `${path}.${process.pid}.tmp`;
  await writeFile(temporary, JSON.stringify(value, null, 2), { mode: 0o600 });
  await rename(temporary, path);
}
export function assertDatabaseUrl(value, admin = false) {
  const url = new URL(value);
  if (url.protocol !== 'postgresql:' || url.hostname !== 'broker-https-postgres' ||
      (admin ? url.pathname !== '/postgres' : !/^\/jrc_test_[a-z0-9_]+$/.test(url.pathname))) {
    throw new Error('UNEXPECTED_FIXTURE_DATABASE');
  }
  if (!admin && url.username !== 'jrc_app') throw new Error('REAL_TENANT_ROLE_REQUIRED');
  return value;
}
export async function openTenantPool() {
  const saved = await readJson('broker-database.private.json');
  return new Pool({ connectionString: assertDatabaseUrl(saved.app_url), max: 4 });
}
export async function custodyCounts(pool, context, otherOrganization) {
  const { withOrganizationTransaction } = await brokerModule('db/tenant-transaction.js');
  return withOrganizationTransaction(pool, context.organization_id, async tx => {
    const eventKey = `message:${context.message_id}`;
    const jobKey = `reply:1:${context.account_id}:${context.inbox_id}:${context.message_id}`;
    const observations = (await tx.query(`SELECT id,event_key FROM chatwoot_attendance_observations
      WHERE organization_id=$1 AND integration_id=$2 AND destination_revision=1 AND account_id=$3 AND inbox_id=$4 AND event_key=$5`,
    [context.organization_id, context.integration_id, context.account_id, context.inbox_id, eventKey])).rows;
    const jobs = (await tx.query(`SELECT id,dedupe_key,status FROM integration_jobs WHERE organization_id=$1
      AND integration_id=$2 AND kind='CHATWOOT_REPLY' AND dedupe_key=$3`,
    [context.organization_id, context.integration_id, jobKey])).rows;
    const cross = (await tx.query('SELECT count(*)::int AS total FROM chatwoot_attendance_observations WHERE organization_id=$1', [otherOrganization])).rows[0].total;
    return { organization_id: context.organization_id, integration_id: context.integration_id,
      observations: observations.length, reply_jobs: jobs.length, cross_tenant_observations: cross,
      event_key: observations[0]?.event_key ?? null, job_dedupe_key: jobs[0]?.dedupe_key ?? null,
      observation_ids: observations.map(row => row.id), job_ids: jobs.map(row => row.id), job_states: jobs.map(row => row.status),
      database_role: 'jrc_app', physical_transport_worker_started: false };
  });
}
