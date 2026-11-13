import assert from 'node:assert/strict';
import { test } from 'node:test';
import { spawn } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, chmodSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { LIMITS, resourceReason, sampleResources, viteCommand } from './jrc_vite_build.mjs';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const wrapper = readFileSync(join(root, 'script/jrc_vite_build.mjs'), 'utf8');
const good = { availableMemory: 8 * 1024 ** 3, diskFree: 3 * 1024 ** 3 };

function fixture(mode = 'probe') {
  const dir = mkdtempSync(join(tmpdir(), 'jrc-vite-heap-'));
  mkdirSync(join(dir, 'script'));
  mkdirSync(join(dir, 'node_modules/vite/bin'), { recursive: true });
  writeFileSync(join(dir, 'package.json'), JSON.stringify({ type: 'module' }));
  writeFileSync(join(dir, 'script/jrc_vite_build.mjs'), wrapper);
  chmodSync(join(dir, 'script/jrc_vite_build.mjs'), 0o755);
  writeFileSync(join(dir, 'node_modules/vite/package.json'), JSON.stringify({
    name: 'vite', version: 'fixture-only', type: 'module',
    exports: { './package.json': './package.json' }, bin: { vite: 'bin/vite.js' },
  }));
  const cli = mode === 'hang'
    ? "console.log('OWNED_FIXTURE_READY'); setInterval(() => {}, 1000);"
    : [
      "import v8 from 'node:v8';",
      "console.log(JSON.stringify({ fixtureOnly: true, heapLimit: v8.getHeapStatistics().heap_size_limit, execArgv: process.execArgv, argv: process.argv.slice(2), nodeOptions: process.env.NODE_OPTIONS, pid: process.pid }));",
      'process.exitCode = ' + (mode === 'fail' ? 17 : 0) + ';',
    ].join('\n');
  writeFileSync(join(dir, 'node_modules/vite/bin/vite.js'), cli);
  return dir;
}

function invoke(dir, heap = '6144') {
  const child = spawn(process.execPath, [join(dir, 'script/jrc_vite_build.mjs'), 'build', '--mode', 'production'], {
    cwd: dir, env: { ...process.env, JRC_VITE_BUILD_HEAP_MIB: heap,
      NODE_OPTIONS: '--max-old-space-size=4096 --openssl-legacy-provider' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let out = '';
  let err = '';
  child.stdout.on('data', data => { out += data; });
  child.stderr.on('data', data => { err += data; });
  return { child, result: new Promise((done, reject) => {
    child.once('error', reject);
    child.once('close', code => done({ code, out, err }));
  }) };
}

test('6144 MiB heap has a stricter 8 GiB process budget and unchanged disk/reserves', () => {
  assert.equal(LIMITS.heapMiB, 6144);
  assert.equal(LIMITS.startMemory, 8 * 1024 ** 3);
  assert.equal(LIMITS.startDisk, 3 * 1024 ** 3);
  assert.equal(LIMITS.reserveMemory, 750 * 1024 ** 2);
  assert.equal(LIMITS.reserveDisk, 750_000_000);
});

test('allows exact start boundaries', () => {
  assert.equal(resourceReason(good, true), null);
});

test('rejects process memory below the start budget', () => {
  assert.equal(resourceReason({ ...good, availableMemory: good.availableMemory - 1 }, true), 'effective_memory_below_8_GiB');
});

test('rejects disk below the start budget', () => {
  assert.equal(resourceReason({ ...good, diskFree: good.diskFree - 1 }, true), 'disk_below_3_GiB');
});

test('rejects the memory reserve including equality', () => {
  assert.equal(resourceReason({ ...good, availableMemory: LIMITS.reserveMemory }), 'memory_reserve_reached');
  assert.equal(resourceReason({ ...good, availableMemory: LIMITS.reserveMemory - 1 }), 'memory_reserve_reached');
  assert.equal(resourceReason({ ...good, availableMemory: LIMITS.reserveMemory + 1 }), null);
});

test('rejects the disk reserve including equality', () => {
  assert.equal(resourceReason({ ...good, diskFree: LIMITS.reserveDisk }), 'disk_reserve_reached');
  assert.equal(resourceReason({ ...good, diskFree: LIMITS.reserveDisk - 1 }), 'disk_reserve_reached');
  assert.equal(resourceReason({ ...good, diskFree: LIMITS.reserveDisk + 1 }), null);
});

test('samples actual process and physical availability conservatively', () => {
  const sample = sampleResources(root);
  assert(sample.processAvailable > 0 && sample.hostAvailable > 0);
  assert.equal(sample.availableMemory, Math.min(sample.processAvailable, sample.hostAvailable));
  assert(sample.diskFree > 0);
});

test('changes only the Vite child CLI while preserving the requested Vite arguments', () => {
  const dir = fixture();
  const env = { ...process.env };
  const args = ['build', '--mode', 'production', '--emptyOutDir'];
  const [exe, command] = viteCommand(dir, args);
  assert.equal(exe, process.execPath);
  assert.equal(command[0], '--max-old-space-size=6144');
  assert.deepEqual(command.slice(2), args);
  assert.deepEqual(process.env, env);
});

test('refuses dev, preview, missing or non-production mode', () => {
  for (const args of [[], ['dev'], ['preview'], ['build'], ['build', '--mode', 'development']]) {
    assert.throws(() => viteCommand(root, args), /only Vite build/);
  }
});

test('actual Node child gets 6 GiB; parent NODE_OPTIONS is not changed', async () => {
  const before = process.env.NODE_OPTIONS;
  const { code, out, err } = await invoke(fixture()).result;
  assert.equal(code, 0, out + err);
  const data = out.split('\n').filter(Boolean).map(line => JSON.parse(line));
  const spy = data.find(line => line.fixtureOnly);
  assert(spy.heapLimit >= 6144 * 1024 ** 2 && spy.heapLimit < 6656 * 1024 ** 2);
  assert.deepEqual(spy.execArgv, ['--max-old-space-size=6144']);
  assert.equal(spy.nodeOptions, '--max-old-space-size=4096 --openssl-legacy-provider');
  assert.equal(process.env.NODE_OPTIONS, before);
  assert(data.find(line => line.passed === true));
});

test('child failure is propagated rather than converted into success', async () => {
  const { code, out } = await invoke(fixture('fail')).result;
  assert.equal(code, 1);
  assert(out.includes('"passed":false') && out.includes('"code":17'));
});

test('unapproved heap configuration fails before the fixture CLI starts', async () => {
  const { code, out, err } = await invoke(fixture(), '8192').result;
  assert.equal(code, 1);
  assert(!out.includes('"fixtureOnly":true'));
  assert(err.includes('Explicit Linux frontend heap configuration required'));
});

test('termination reaches only the owned Vite; independent process stays alive', { timeout: 20_000 }, async () => {
  const independent = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], { stdio: 'ignore' });
  const owned = invoke(fixture('hang'));
  try {
    await new Promise((done, reject) => {
      const timer = setTimeout(() => reject(new Error('Owned fixture did not start')), 10_000);
      owned.child.stdout.on('data', data => {
        if (data.toString().includes('OWNED_FIXTURE_READY')) { clearTimeout(timer); done(); }
      });
      owned.child.once('exit', () => { clearTimeout(timer); reject(new Error('Wrapper exited before fixture startup')); });
    });
    owned.child.kill('SIGTERM');
    const result = await owned.result;
    assert.equal(result.code, 1);
    assert(result.out.includes('termination_requested'));
    assert.equal(independent.exitCode, null);
    assert.equal(independent.signalCode, null);
  } finally {
    if (owned.child.exitCode === null) owned.child.kill('SIGTERM');
    independent.kill('SIGTERM');
  }
});
