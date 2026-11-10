import assert from 'node:assert/strict';
import test from 'node:test';
import { inspectMigrationIdentities } from './validate_ag_migration_identity.mjs';

test('independent versions do not conflict', () => {
  assert.deepEqual(inspectMigrationIdentities([
    '20261109190000_create_backoffice_requirement_catalog.rb',
    '20261109191000_create_portfolio_history_receipts.rb',
  ]), []);
});

test('same version in independent histories is a blocking conflict', () => {
  const files = [
    '20261102090000_create_jrc_broker_webhook_obligations.rb',
    '20261102090000_create_backoffice_signature_deliveries.rb',
  ];
  assert.deepEqual(inspectMigrationIdentities(files), [{ version: '20261102090000', files: [...files].sort() }]);
  assert.deepEqual(files, [
    '20261102090000_create_jrc_broker_webhook_obligations.rb',
    '20261102090000_create_backoffice_signature_deliveries.rb',
  ]);
});

test('reports every collision in a deterministic order', () => {
  assert.deepEqual(inspectMigrationIdentities([
    '20261102100000_human_assignment.rb', '20261102090000_signature.rb',
    '20261102100000_reconciliation.rb', '20261102090000_broker.rb',
  ]).map(row => row.version), ['20261102090000', '20261102100000']);
});

test('rejects an identity without a fourteen-digit version', () => {
  assert.throws(() => inspectMigrationIdentities(['signature.rb']), /Invalid migration filename/);
});
