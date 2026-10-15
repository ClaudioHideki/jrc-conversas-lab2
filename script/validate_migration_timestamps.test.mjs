import assert from 'node:assert/strict';
import { test } from 'node:test';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateNewMigrationTimestamps } from './validate_migration_timestamps.mjs';

const baseSchema = 'ActiveRecord::Schema[7.1].define(version: 2026_10_12_160000) do\nend\n';

test('rejects the new 0918 migration skipped by a schema loaded at the reviewed base version', () => {
  assert.throws(
    () => validateNewMigrationTimestamps(baseSchema, ['db/migrate/20261009180000_create_jrc_flow_native_registrations.rb']),
    /20261009180000.*20261012160000/
  );
});

test('accepts the pre-release 131400 replacement after the reviewed base schema version', () => {
  assert.doesNotThrow(() => validateNewMigrationTimestamps(baseSchema, [
    'db/migrate/20261013140000_create_jrc_flow_native_registrations.rb',
  ]));
});

test('also rejects a new migration equal to the reviewed base schema version', () => {
  assert.throws(
    () => validateNewMigrationTimestamps(baseSchema, ['db/migrate/20261012160000_untracked_candidate.rb']),
    /20261012160000/
  );
});

test('fails closed when the reviewed base schema version cannot be read', () => {
  assert.throws(() => validateNewMigrationTimestamps('not a Rails schema', []), /base schema version/i);
});

for (const [timestamp, accepted] of [['20261009180000', false], ['20261015120000', true]]) {
  test(`CLI validates the destination of a staged R100 migration rename to ${timestamp}`, () => {
    const fixture = mkdtempSync(path.join(tmpdir(), 'jrc-migration-rename-'));
    const git = (...args) => execFileSync('git', args, { cwd: fixture, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    try {
      mkdirSync(path.join(fixture, 'db/migrate'), { recursive: true });
      writeFileSync(path.join(fixture, 'db/schema.rb'), baseSchema);
      const previous = 'db/migrate/20261014120000_create_fixture.rb';
      const next = `db/migrate/${timestamp}_create_fixture.rb`;
      writeFileSync(path.join(fixture, previous), 'class CreateFixture < ActiveRecord::Migration[7.1]\nend\n');
      git('init', '--quiet');
      git('add', '.');
      git('-c', 'user.name=Migration Test', '-c', 'user.email=migration@example.test',
        '-c', 'commit.gpgsign=false', 'commit', '--quiet', '-m', 'Reviewed fixture');
      const base = git('rev-parse', 'HEAD').trim();
      git('mv', previous, next);
      assert.equal(git('diff', '--cached', '--name-status', '--find-renames', base).trim(), `R100\t${previous}\t${next}`);
      const cli = fileURLToPath(new URL('./validate_changed_source.mjs', import.meta.url));
      const result = spawnSync(process.execPath, [cli, base], { cwd: fixture, encoding: 'utf8', timeout: 30_000 });
      assert.ifError(result.error);
      if (accepted) {
        assert.equal(result.status, 0, result.stderr);
        assert.match(result.stdout, /Validated 1 new migrations after base schema 20261012160000/);
      } else {
        assert.equal(result.status, 1, result.stdout);
        assert.match(result.stderr, /20261009180000.*must sort after.*20261012160000/);
      }
    } finally {
      assert.equal(path.dirname(path.resolve(fixture)), path.resolve(tmpdir()));
      assert.ok(path.basename(fixture).startsWith('jrc-migration-rename-'));
      rmSync(fixture, { recursive: true, force: true });
    }
  });
}
