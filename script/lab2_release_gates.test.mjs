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

test('main retains the native regression and exact-SHA image release gates after promotion', () => {
  assert.match(native.split('pull_request:')[0], /^\s+- main\s*$/m);
  assert.match(build, /github\.ref_name == 'main'/);
  assert.match(build, /main\|codex\/crm-backoffice-servicedesk-visual-20261101/);
  assert.match(build, /run\['head_sha'\] == os\.environ\['SOURCE_SHA'\]/);
  assert.match(build, /run\['head_branch'\] == os\.environ\['GITHUB_REF_NAME'\]/);
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

test('the consolidated release rejects stale Flow ownership manifests before Rails validation', () => {
  const integrationJob = native.split('  broker-and-import-integration:')[1];
  const checkout = integrationJob.slice(integrationJob.indexOf('uses: actions/checkout@'), integrationJob.indexOf('- name: Dependencias nativas'));
  assert.match(checkout, /fetch-depth: 0/, 'the manifest verifier needs its exact historical Git base');
  const manifestGate = native.indexOf('node script/jrc_native_module_manifest.mjs');
  const railsGate = native.indexOf('name: Regressao de contratos e integridade');
  assert.ok(manifestGate >= 0, 'the release must verify the frozen module manifest');
  assert.ok(manifestGate < railsGate, 'verify source hashes before exercising the candidate');
  assert.doesNotMatch(native, /jrc_native_module_manifest\.mjs\s+--write/);
});

test('the MinIO fixture is retrievable from its official release and verified before execution', () => {
  assert.equal(native.includes('minio/minio@sha256:'), false);
  assert.equal(native.includes('https://github.com/minio/minio/releases/download/RELEASE.2025-09-07T16-13-09Z/'), true);
  assert.equal(native.includes('7c5bd8512c6e966455b1d198209358b2d191c77a83ab377c4073281065fb855f'), true);
  assert.equal(native.includes('sha256sum --check'), true);
});
