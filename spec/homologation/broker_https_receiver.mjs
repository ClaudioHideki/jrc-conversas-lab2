// Actual Fastify buildApp + ChatwootService + tenant transactions from the pinned API image.
import { randomUUID } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { origin, settings, brokerModule, readJson, writeJson, assertDatabaseUrl, Pool, openTenantPool } from './broker_https_broker.mjs';

if (process.argv[2] === 'seed') {
  const { createIsolatedPostgresDatabase } = await import(pathToFileURL('/app/broker-test-helpers/postgres.ts').href);
  const { withGlobalRoleLock } = await import(pathToFileURL('/app/broker-test-helpers/global-role-lock.ts').href);
  const { runMigrations } = await brokerModule('db/migrate.js');
  const { createOrganization, runInAdminTransaction } = await brokerModule('modules/organizations/repository.js');
  const { withOrganizationTransaction } = await brokerModule('db/tenant-transaction.js');
  const { ensureQrChannel } = await brokerModule('modules/messaging/qr-service.js');
  const { createIntegrationSecrets } = await brokerModule('modules/integrations/secrets.js');
  const adminUrl = assertDatabaseUrl(settings.broker_admin_url, true);
  const database = await createIsolatedPostgresDatabase(adminUrl);
  await withGlobalRoleLock(adminUrl, () => runMigrations(database.connectionString));
  if (!/^[a-f0-9]{32,128}$/.test(settings.broker_app_password)) throw new Error('SYNTHETIC_APP_PASSWORD_REQUIRED');
  await database.pool.query(`ALTER ROLE jrc_app LOGIN PASSWORD '${settings.broker_app_password}'`);
  const appUrl = new URL(database.connectionString);
  appUrl.username = 'jrc_app'; appUrl.password = settings.broker_app_password;
  const pool = new Pool({ connectionString: appUrl.toString(), max: 2 });
  const vault = createIntegrationSecrets(settings.integration_encryption_key);
  const contexts = [];
  for (const key of ['a', 'b']) {
    const participant = await readJson(`participant_${key}.json`);
    if (participant.key !== key || participant.database !== `jrc_broker_https_${key}_test` ||
        participant.chatwoot_origin !== `https://lab2-${key}.example.test` || typeof participant.webhook_secret !== 'string') {
      throw new Error('UNEXPECTED_RAILS_PARTICIPANT');
    }
    const org = await runInAdminTransaction(database.pool, async tx => {
      const organization = await createOrganization(tx, { name: `Broker HTTPS lab ${key}`, slug: `broker-https-${key}-${settings.run_id}` });
      const user = (await tx.query("INSERT INTO users(email,password_hash) VALUES($1,'synthetic-unused-password') RETURNING id",
        [`${randomUUID()}@example.test`])).rows[0];
      await tx.query("INSERT INTO memberships(organization_id,user_id,role) VALUES($1,$2,'OWNER')", [organization.id, user.id]);
      return organization.id;
    });
    const context = await withOrganizationTransaction(pool, org, async tx => {
      const provider = (await tx.query(`INSERT INTO provider_accounts(organization_id,provider,name)
        VALUES($1,'BAILEYS','Synthetic fixture - no physical I/O') RETURNING id`, [org])).rows[0].id;
      const instance = (await tx.query(`INSERT INTO instances(organization_id,provider_account_id,name,upstream_instance_key,status)
        VALUES($1,$2,'Synthetic fixture - no physical I/O',$3,'CREATED') RETURNING id`, [org, provider, `synthetic-${randomUUID()}`])).rows[0].id;
      const channel = await ensureQrChannel(tx, org, instance);
      const integration = randomUUID();
      await tx.query(`INSERT INTO chatwoot_accounts(organization_id,base_url,account_id,encrypted_token,status)
        VALUES($1,$2,$3,$4,'READY')`, [org, participant.chatwoot_origin, participant.account_id,
        vault.encrypt(`${org}:chatwoot-account`, 'synthetic-unused-control-token')]);
      await tx.query(`INSERT INTO chatwoot_connections(id,organization_id,channel_id,inbox_id,name,encrypted_webhook_secret,status)
        VALUES($1,$2,$3,$4,'Synthetic signed callback',$5,'READY')`, [integration, org, channel.id, participant.inbox_id,
        vault.encrypt(`${org}:chatwoot-webhook:${integration}`, participant.webhook_secret)]);
      return { ...participant, organization_id: org, integration_id: integration, instance_id: instance,
        channel_id: channel.id, destination_revision: 1 };
    });
    contexts.push(context);
  }
  if (contexts[0].account_id !== contexts[1].account_id || contexts[0].inbox_id !== contexts[1].inbox_id) throw new Error('FIXTURE_IDS_DO_NOT_COLLIDE');
  await writeJson('broker-database.private.json', { database: database.databaseName, app_url: appUrl.toString() });
  await writeJson('manifest.json', { run_id: settings.run_id, control_token: settings.control_token, contexts });
  await pool.end(); await database.pool.end();
  // The integration helper owns a private admin pool; no dispose() is called because it drops the DB.
  process.stdout.write(JSON.stringify({ seeded: 2, database: database.databaseName, real_migrations: true,
    helper: 'integration/helpers/postgres.ts', preserved_database: true }) + '\n', () => process.exit(0));
} else if (process.argv[2] === 'serve') {
  const { buildApp } = await brokerModule('app.js');
  const { createChatwootService } = await brokerModule('modules/integrations/chatwoot-service.js');
  const { withOrganizationTransaction } = await brokerModule('db/tenant-transaction.js');
  const pool = await openTenantPool();
  const service = createChatwootService({ publicOrigin: origin, encryptionKey: settings.integration_encryption_key,
    transact: (org, work) => withOrganizationTransaction(pool, org, work),
    resolveIntegration: async id => (await pool.query('SELECT organization_id FROM resolve_chatwoot_integration($1)', [id])).rows[0]?.organization_id });
  const app = buildApp({ nodeEnv: 'test', integrations: { jwtSecret: settings.control_token, service,
    resolveCurrentRole: async (user, org) => withOrganizationTransaction(pool, org, async tx =>
      (await tx.query('SELECT role FROM memberships WHERE organization_id=$1 AND user_id=$2', [org, user])).rows[0]?.role ?? null) } });
  await app.listen({ host: '0.0.0.0', port: 8080 });
  console.log(JSON.stringify({ real_broker_ingress: true, real_postgres_tenant_transactions: true,
    route: '/v1/integrations/chatwoot/:id/events', role: 'jrc_app', physical_transport_worker_started: false }));
  for (const signal of ['SIGTERM', 'SIGINT']) process.on(signal, async () => { await app.close(); await pool.end(); process.exit(0); });
} else {
  throw new Error('UNKNOWN_HTTPS_BROKER_PHASE');
}
