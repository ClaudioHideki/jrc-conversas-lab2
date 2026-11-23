import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const REQUIRED = new Map([
  ['spec/services/jrc_contact_center/confirm_ending_reason_spec.rb', 13],
  ['spec/services/jrc_contact_center/confirm_ending_reason_forms_spec.rb', 2],
  ['spec/requests/api/v1/accounts/jrc_contact_center/ending_reason_confirmation_spec.rb', 8],
]);

// A short native preflight, never a replacement for the full mandatory suites.
export function validatePreflight(data) {
  const { summary, examples } = data;
  assert.equal(summary.example_count, 23);
  for (const key of ['failure_count', 'pending_count', 'errors_outside_of_examples_count']) {
    assert.equal(summary[key], 0);
  }
  assert.equal(examples.length, 23);
  const counts = new Map();
  const identities = new Set();
  for (const row of examples) {
    assert.equal(row.status, 'passed');
    const path = row.file_path.replace(/^\.\//, '');
    assert(REQUIRED.has(path));
    assert(Number.isInteger(row.line_number) && row.line_number > 0);
    assert(typeof row.full_description === 'string' && row.full_description.length > 0);
    const identity = JSON.stringify([path, row.line_number, row.full_description]);
    assert(!identities.has(identity));
    identities.add(identity);
    counts.set(path, (counts.get(path) || 0) + 1);
  }
  assert.deepEqual(counts, REQUIRED);
  return summary;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  console.log(JSON.stringify(validatePreflight(JSON.parse(readFileSync(process.argv[2], 'utf8')))));
}
