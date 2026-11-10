import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
const read = file => readFileSync(new URL('../' + file, import.meta.url), 'utf8');
test('consolidation branches retain native validation and same-SHA image gates', () => {
  const native = read('.github/workflows/backoffice-flow.yml');
  const voice = read('.github/workflows/voice-v4-candidate.yml');
  const build = read('.github/workflows/build-ghcr.yml');
  assert.match(native.split('pull_request:')[0], /codex\/consolidacao-\*/);
  assert.match(voice.split('workflow_dispatch:')[0], /codex\/consolidacao-\*/);
  assert.match(build, /startsWith\(github.ref_name, 'codex\/consolidacao-'\)/);
  assert.match(build, /codex\/consolidacao-\*/);
  assert.match(build, /run\['head_sha'\] == os\.environ\['SOURCE_SHA'\]/);
  assert.match(build, /run\['head_branch'\] == os\.environ\['GITHUB_REF_NAME'\]/);
  assert.ok(native.includes('script/release_alignment_gates.test.mjs'));
  assert.ok(native.includes('script/jrc_native_module_manifest.test.mjs'));
});

test('consolidated releases also require the exact Projects and Portal validation', () => {
  const projects = read('.github/workflows/projects-portal-candidate.yml');
  const build = read('.github/workflows/build-ghcr.yml');
  assert.ok(projects.includes("'codex/consolidacao-*'"));
  assert.ok(projects.includes("'main'"));
  const gate = build.split('- name: Exigir Projetos e Portal tambem na release consolidada')[1].split('- name: Baixar a revisao exata')[0];
  assert.ok(gate.includes("github.ref_name == 'main'"));
  assert.ok(gate.includes("startsWith(github.ref_name, 'codex/consolidacao-')"));
  assert.ok(gate.includes('inputs.projects_validation_run_id'));
  assert.ok(gate.includes("run['head_sha'] == os.environ['SOURCE_SHA']"));
  assert.ok(gate.includes("run['head_branch'] == os.environ['GITHUB_REF_NAME']"));
  assert.ok(gate.includes("run['path'] == '.github/workflows/projects-portal-candidate.yml'"));
  assert.ok(gate.includes("run['conclusion'] == 'success'"));
});

test('Projects validation uses each product baseline and the guarded concurrency databases', () => {
  const workflow = read('.github/workflows/projects-portal-candidate.yml');
  assert.ok(workflow.includes('EXTENSION-REFERENCE.json'));
  assert.ok(workflow.includes('extensionBaselineSha'));
  assert.ok(workflow.includes('git merge-base --is-ancestor "$baseline" HEAD'));
  assert.ok(workflow.includes('git diff --name-only --diff-filter=ACMR "$REVIEW_BASE_SHA" HEAD'));
  assert.ok(workflow.includes('bundle exec rubocop --force-exclusion --only Lint'));
  assert.ok(workflow.includes('POSTGRES_DATABASE: jrc_sd_integrated_concurrency_20261023_test'));
  assert.ok(workflow.includes("JRC_SD_INTEGRATED_CONCURRENCY: '1'"));
  assert.ok(workflow.includes('POSTGRES_DATABASE: jrc_four_fronts_concurrency_20261026_test'));
  assert.ok(workflow.includes("JRC_PROJECT_COMMENT_CONCURRENCY: '1'"));
});

test('consolidation exercises legacy NICO and Flow gates and keeps committed routing fixtures isolated', () => {
  const nico = read('.github/workflows/nico-broker-candidate.yml');
  const flow = read('.github/workflows/flow-broker-candidate.yml');
  for (const workflow of [nico, flow]) {
    assert.ok(workflow.includes('codex/consolidacao-*'));
    assert.ok(workflow.includes('refs/heads/codex/consolidacao-*'));
  }
  assert.ok(flow.includes('--exclude-pattern spec/services/jrc_broker/routing_context_connection_spec.rb'));
  assert.ok(flow.includes('POSTGRES_DATABASE: jrc_durable_review_test'));
  assert.ok(flow.includes('bundle exec rspec spec/services/jrc_broker/routing_context_connection_spec.rb'));
});
