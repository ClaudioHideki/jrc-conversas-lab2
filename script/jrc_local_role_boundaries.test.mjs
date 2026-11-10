import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const moduleURL = new URL('../app/javascript/dashboard/routes/dashboard/jrcRelationship/localRoleDraft.js', import.meta.url);
const source = await readFile(moduleURL, 'utf8');
const { localRoleDraft, validateLocalRoleDraft, ROLE_ACTION_LIMITS, editableRoleActions, editableRoleGrants, LOCAL_ACTIONS } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const denied = {
  viewer: ['work', 'team', 'configure', 'manage_portfolios', 'request_transfer', 'approve_transfer', 'execute_transfer', 'request_eligibility', 'manage_eligibility', 'document_upload', 'document_replace', 'document_manage'],
  analyst: ['configure', 'manage_portfolios', 'approve_transfer', 'execute_transfer', 'request_eligibility', 'manage_eligibility', 'document_manage', 'document_restricted'],
  supervisor: ['configure', 'manage_portfolios', 'execute_transfer', 'manage_eligibility', 'document_manage', 'document_upload', 'document_replace'],
};
for (const [name, actions] of Object.entries(denied)) {
  for (const action of actions) test(`${name} cannot acquire ${action} through configuration`, () => {
    const draft = localRoleDraft(null);
    draft.enabled = true;
    draft.roles[name].actions.push(action);
    assert.equal(validateLocalRoleDraft(draft), false);
  });
}

test('manager may narrow its capabilities without changing presets', () => {
  const draft = localRoleDraft(null);
  draft.roles.manager.actions = ['view'];
  assert.equal(validateLocalRoleDraft(draft), true);
  assert.deepEqual(localRoleDraft(null).roles.manager.actions, LOCAL_ACTIONS);
});
test('an incompatible old choice remains visible so it can be removed explicitly', () => {
  assert(editableRoleActions('viewer', ['view', 'work']).includes('work'));
  assert(!editableRoleActions('viewer').includes('work'));
});
test('independent grants cannot present operational write actions', () => {
  assert(!editableRoleGrants('viewer').includes('document_upload'));
  assert(editableRoleGrants('viewer').includes('document_download'));
});
test('explicit read-only export capabilities remain configurable, not preset', () => {
  const draft = localRoleDraft(null);
  draft.roles.viewer.actions.push('export_data');
  assert.equal(validateLocalRoleDraft(draft), true);
  assert(!localRoleDraft(null).roles.viewer.actions.includes('export_data'));
});
test('configuration validation preserves the draft for correction', () => {
  const draft = localRoleDraft(null);
  draft.roles.viewer.actions.push('work');
  const before = JSON.stringify(draft);
  assert.equal(validateLocalRoleDraft(draft), false);
  assert.equal(JSON.stringify(draft), before);
});
test('Ruby and frontend enforce identical role ceilings', () => {
  const path = fileURLToPath(new URL('../app/services/jrc_relationship/local_role_rules.rb', import.meta.url));
  const result = spawnSync('ruby', ['-rjson', '-e', 'module JrcRelationship; end; require ARGV.fetch(0); puts JSON.generate(JrcRelationship::LocalRoleRules::ROLE_ACTION_LIMITS)', path], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  const native = JSON.parse(result.stdout);
  for (const role of Object.keys(ROLE_ACTION_LIMITS)) assert.deepEqual([...native[role]].sort(), [...ROLE_ACTION_LIMITS[role]].sort());
});
