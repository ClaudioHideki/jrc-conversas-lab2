import assert from 'node:assert/strict';
import test from 'node:test';
import { parseMigrationFile } from '../migrationFile.js';

test('rejects an unescaped quote inside an unquoted field instead of changing source data', () => {
  assert.throws(() => parseMigrationFile('id,name\n1,bad"quote"', 'source.csv'));
});

test('rejects characters after a closing quote instead of joining them into the value', () => {
  assert.throws(() => parseMigrationFile('id,name\n1,"closed"suffix', 'source.csv'));
});

test('preserves escaped quotes, separators, source IDs and multiline content', () => {
  assert.deepEqual(parseMigrationFile('id,name\r\n0001,"a, ""quote""\nline"\r\n', 'source.csv'), [
    { id: '0001', name: 'a, "quote"\nline' },
  ]);
});
