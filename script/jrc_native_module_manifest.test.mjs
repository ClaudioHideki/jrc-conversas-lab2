import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { test } from 'node:test';
import * as manifest from './jrc_native_module_manifest.mjs';

test('batch base reads preserve exact text and binary bytes and distinguish missing paths', () => {
  const root = mkdtempSync(join(tmpdir(), 'jrc-manifest-batch-'));
  const git = (...args) => execFileSync('git', ['-c', `safe.directory=${root.replaceAll('\\', '/')}`, '-C', root, ...args], { encoding: 'utf8' });
  try {
    git('init', '-q');
    mkdirSync(join(root, 'app'));
    const text = Buffer.from('ação\r\n');
    const binary = Buffer.from([0, 255, 10]);
    writeFileSync(join(root, 'app/source.rb'), text);
    writeFileSync(join(root, 'payload.bin'), binary);
    writeFileSync(join(root, '.gitattributes'), '* -text\n');
    git('add', '.');
    git('-c', 'user.name=JRC Tests', '-c', 'user.email=tests@example.invalid', 'commit', '-qm', 'synthetic manifest fixture');
    const sha = git('rev-parse', 'HEAD').trim();
    const blobs = manifest.readBaseBlobs(root, sha, ['app/source.rb', 'payload.bin', 'absent.rb']);
    assert.deepEqual(blobs.get('app/source.rb'), text);
    assert.deepEqual(blobs.get('payload.bin'), binary);
    assert.equal(blobs.get('absent.rb'), null);
    assert.throws(() => manifest.readBaseBlobs(root, sha, ['app/source.rb\nHEAD:payload.bin']), /Unsafe/);
  } finally {
    assert.ok(root.startsWith(join(tmpdir(), 'jrc-manifest-batch-')));
    rmSync(root, { recursive: true, force: true });
  }
});