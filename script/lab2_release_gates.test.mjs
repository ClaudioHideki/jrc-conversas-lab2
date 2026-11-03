import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const branch = 'codex/lab2-integral-20261102';
const native = readFileSync(new URL('../.github/workflows/backoffice-flow.yml', import.meta.url), 'utf8');
const build = readFileSync(new URL('../.github/workflows/build-ghcr.yml', import.meta.url), 'utf8');
const smoke = readFileSync(new URL('./smoke_backoffice_candidate.sh', import.meta.url), 'utf8');

test('the integral candidate triggers native validation and cannot bypass its image gate', () => {
  assert.match(native.split('pull_request:')[0], new RegExp(branch));
  assert.match(build, /github\.ref_name == 'codex\/lab2-integral-20261102'/);
  assert.match(build, /codex\/lab2-integral-20261102\) ;;/);
});

test('every schema-loaded validation database applies SQL guards without dumping source', () => {
  assert.doesNotMatch(native, /rails db:prepare/);
  assert.equal((native.match(/rails runner script\/prepare_lab2_candidate_database.rb/g) || []).length, 3);
  assert.match(smoke, /rails runner script\/prepare_lab2_candidate_database.rb/);
});

test('native validation includes migration media and NICO permission regressions', () => {
  assert.match(native, /spec\/services\/jrc_migrations/);
  assert.match(native, /spec\/requests\/jrc_migration\*_spec.rb/);
  assert.match(native, /spec\/services\/jrc_nico\/migration\*_spec.rb/);
  assert.match(native, /JRC_IMPORT_MINIO_ENDPOINT/);
});
