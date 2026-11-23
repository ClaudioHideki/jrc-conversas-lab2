import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const REQUIRED = new Map([
  ['spec/services/jrc_contact_center/ending_actions/task_definition_spec.rb', 25],
  ['spec/services/jrc_contact_center/ending_actions/rule_definition_spec.rb', 34],
  ['spec/services/jrc_contact_center/ending_actions/catalogue_spec.rb', 1],
  ['spec/models/jrc_contact_center/ending_action_version_spec.rb', 9],
  ['spec/services/jrc_contact_center/create_contact_center_ending_action_versions_spec.rb', 5],
  ['spec/services/jrc_contact_center/ending_actions/configure_rule_spec.rb', 11],
  ['spec/requests/api/v1/accounts/jrc_contact_center/ending_action_definition_privacy_spec.rb', 4],
]);

// Reader fixtures do not confer native acceptance: this command consumes the real RSpec formatter output.
export function validateVersionPreflight(data) {
  const total = [...REQUIRED.values()].reduce((sum, value) => sum + value, 0);
  assert.equal(data.summary.example_count, total);
  for (const key of ['failure_count', 'pending_count', 'errors_outside_of_examples_count']) {
    assert.equal(data.summary[key], 0);
  }
  assert.equal(data.examples.length, total);
  const counts = new Map();
  const identities = new Set();
  for (const row of data.examples) {
    const path = row.file_path.replace(/^\.\//, '');
    assert(REQUIRED.has(path) && row.status === 'passed');
    assert(Number.isInteger(row.line_number) && row.line_number > 0);
    assert(typeof row.full_description === 'string' && row.full_description.length > 0);
    const identity = JSON.stringify([path, row.line_number, row.full_description]);
    assert(!identities.has(identity));
    identities.add(identity);
    counts.set(path, (counts.get(path) || 0) + 1);
  }
  assert.deepEqual(counts, REQUIRED);
  return data.summary;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  console.log(JSON.stringify(validateVersionPreflight(JSON.parse(readFileSync(process.argv[2], 'utf8')))));
}
