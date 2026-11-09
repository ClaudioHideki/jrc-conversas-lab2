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
