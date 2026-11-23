import assert from 'node:assert/strict';
import { test } from 'node:test';
import { REQUIRED, validatePreflight } from './validate_cc_ending_confirmation_preflight.mjs';

function fixture() {
  return {
    summary: { example_count: 23, failure_count: 0, pending_count: 0, errors_outside_of_examples_count: 0 },
    examples: [...REQUIRED].flatMap(([path, count]) => Array.from({ length: count }, (_, index) => ({
      file_path: `./${path}`, line_number: index + 1, full_description: `synthetic validator case ${index}`, status: 'passed',
    }))),
  };
}

test('validates complete synthetic reader input, never a claim of Rails acceptance', () => {
  assert.equal(validatePreflight(fixture()).example_count, 23);
});

test('allows out-of-order native rows without discarding or deduplicating them', () => {
  const data = fixture();
  data.examples.reverse();
  assert.equal(validatePreflight(data).example_count, 23);
});

for (const [name, mutate] of [
  ['zero examples', data => { data.summary.example_count = 0; }],
  ['positive failure count', data => { data.summary.failure_count = 1; }],
  ['pending count', data => { data.summary.pending_count = 1; }],
  ['outside errors', data => { data.summary.errors_outside_of_examples_count = 1; }],
  ['failed row despite clean summary', data => { data.examples[0].status = 'failed'; }],
  ['missing row', data => { data.examples.pop(); }],
  ['unknown file', data => { data.examples[0].file_path = './spec/unknown.rb'; }],
  ['duplicate logical example', data => { data.examples[1] = { ...data.examples[0] }; }],
  ['wrong file coverage', data => { data.examples[0].file_path = [...REQUIRED.keys()][1]; }],
  ['missing identity', data => { data.examples[0].full_description = ''; }],
]) {
  test(`rejects ${name}`, () => {
    const data = fixture();
    mutate(data);
    assert.throws(() => validatePreflight(data));
  });
}
