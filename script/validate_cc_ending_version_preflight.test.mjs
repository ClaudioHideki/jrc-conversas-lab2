import assert from 'node:assert/strict';
import { test } from 'node:test';
import { REQUIRED, validateVersionPreflight } from './validate_cc_ending_version_preflight.mjs';

function nativeReportFixture() {
  const examples = [...REQUIRED].flatMap(([path, total]) =>
    Array.from({ length: total }, (_, index) => ({
      file_path: './' + path, line_number: index + 1, full_description: path + '|SYNTHETIC_READER_' + index, status: 'passed',
    }))
  );
  return { summary: { example_count: examples.length, failure_count: 0, pending_count: 0, errors_outside_of_examples_count: 0 }, examples };
}

test('accepts exactly102unique positive fixtures; this does not represent an executed native suite', () => {
  const data = nativeReportFixture();
  assert.equal(validateVersionPreflight(data).example_count, 102);
});

for (const key of ['failure_count', 'pending_count', 'errors_outside_of_examples_count']) {
  test(`rejects any positive ${key}`, () => {
    const data = nativeReportFixture();
    data.summary[key] = 1;
    assert.throws(() => validateVersionPreflight(data));
  });
}

for (const count of [0, 101, 103]) {
  test(`rejects summary example count ${count}`, () => {
    const data = nativeReportFixture();
    data.summary.example_count = count;
    assert.throws(() => validateVersionPreflight(data));
  });
}

for (const status of ['pending', 'failed', 'unknown']) {
  test(`rejects an example with ${status} status`, () => {
    const data = nativeReportFixture();
    data.examples[0].status = status;
    assert.throws(() => validateVersionPreflight(data));
  });
}

test('rejects a duplicate identity instead of silently deduplicating it', () => {
  const data = nativeReportFixture();
  data.examples[1] = { ...data.examples[0] };
  assert.throws(() => validateVersionPreflight(data));
});

test('rejects missing formatter examples even when the summary claims completion', () => {
  const data = nativeReportFixture();
  data.examples.pop();
  assert.throws(() => validateVersionPreflight(data));
});

test('rejects an unreviewed file instead of substituting unrelated green examples', () => {
  const data = nativeReportFixture();
  data.examples[0].file_path = 'spec/SYNTHETIC_UNREVIEWED_spec.rb';
  assert.throws(() => validateVersionPreflight(data));
});

test('rejects a valid-file substitution that loses the required privacy or persistence coverage', () => {
  const data = nativeReportFixture();
  data.examples.at(-1).file_path = data.examples[0].file_path;
  assert.throws(() => validateVersionPreflight(data));
});

for (const change of [{ line_number: 0 }, { line_number: 1.5 }, { full_description: '' }]) {
  test(`rejects missing or malformed identity ${JSON.stringify(change)}`, () => {
    const data = nativeReportFixture();
    Object.assign(data.examples[0], change);
    assert.throws(() => validateVersionPreflight(data));
  });
}
