import assert from 'node:assert/strict';
import { test } from 'node:test';
import { REQUIRED, validateScopePreflight } from './validate_cc_ending_scope_preflight.mjs';

function fixture() {
  return {
    summary: { example_count: 38, failure_count: 0, pending_count: 0, errors_outside_of_examples_count: 0 },
    examples: [...REQUIRED].flatMap(([path, count]) => Array.from({ length: count }, (_, index) => ({
      file_path: `./${path}`, line_number: index + 1, full_description: `synthetic reader case ${index}`, status: 'passed',
    }))),
  };
}

test('accepts complete reader input; this is not a Rails or PostgreSQL test', () => {
  assert.equal(validateScopePreflight(fixture()).example_count, 38);
});

test('accepts out-of-order native results without discarding or deduplicating them', () => {
  const data = fixture();
  data.examples.reverse();
  assert.equal(validateScopePreflight(data).example_count, 38);
});

for (const [name, mutate] of [
  ['zero examples', data => { data.summary.example_count = 0; }],
  ['failure', data => { data.summary.failure_count = 1; }],
  ['pending', data => { data.summary.pending_count = 1; }],
  ['outside error', data => { data.summary.errors_outside_of_examples_count = 1; }],
  ['missing row', data => { data.examples.pop(); }],
  ['unknown source', data => { data.examples[0].file_path = './spec/unknown.rb'; }],
  ['duplicate identity', data => { data.examples[1] = { ...data.examples[0] }; }],
  ['wrong source count', data => { data.examples[0].file_path = [...REQUIRED.keys()][1]; }],
  ['failed row and clean summary', data => { data.examples[0].status = 'failed'; }],
  ['missing description', data => { data.examples[0].full_description = ''; }],
  ['invalid line', data => { data.examples[0].line_number = 0; }],
]) {
  test(`rejects ${name}`, () => {
    const data = fixture();
    mutate(data);
    assert.throws(() => validateScopePreflight(data));
  });
}
