import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const REQUIRED = new Map([
  ['spec/models/jrc_contact_center/ending_action_queue_scope_spec.rb', 15],
  ['spec/services/jrc_contact_center/ending_action_queue_scope_history_spec.rb', 12],
  ['spec/services/jrc_contact_center/create_contact_center_ending_action_scopes_spec.rb', 5],
]);

// Actual PostgreSQL examples are required; synthetic reader tests do not confer native acceptance.
export function validateScopePreflight(data) {
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
  console.log(JSON.stringify(validateScopePreflight(JSON.parse(readFileSync(process.argv[2], 'utf8')))));
}
