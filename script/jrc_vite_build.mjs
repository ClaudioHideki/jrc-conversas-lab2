#!/usr/bin/env node
// Used only by the production assets RUN through VITE_RUBY_VITE_BIN_PATH.
import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { readFileSync, statfsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const LIMITS = Object.freeze({
  heapMiB: 6144,
  startMemory: 8 * 1024 ** 3,
  startDisk: 3 * 1024 ** 3,
  reserveMemory: 750 * 1024 ** 2,
  reserveDisk: 750_000_000,
});

export function resourceReason(sample, starting = false) {
  if (starting && sample.availableMemory < LIMITS.startMemory) return 'effective_memory_below_8_GiB';
  if (starting && sample.diskFree < LIMITS.startDisk) return 'disk_below_3_GiB';
  if (sample.availableMemory <= LIMITS.reserveMemory) return 'memory_reserve_reached';
  if (sample.diskFree <= LIMITS.reserveDisk) return 'disk_reserve_reached';
  return null;
}

export function sampleResources(root) {
  const host = readFileSync('/proc/meminfo', 'utf8').match(/^MemAvailable:\s+(\d+)\s+kB/m);
  if (!host) throw new Error('Linux MemAvailable is required');
  const hostAvailable = Number(host[1]) * 1024;
  const processAvailable = process.availableMemory();
  const constrainedMemory = process.constrainedMemory();
  const fs = statfsSync(root);
  return {
    hostAvailable, processAvailable, constrainedMemory,
    availableMemory: Math.min(hostAvailable, processAvailable),
    diskFree: fs.bavail * fs.bsize,
  };
}

export function viteCommand(root, args) {
  const mode = args.indexOf('--mode');
  if (args[0] !== 'build' || mode < 0 || args[mode + 1] !== 'production') {
    throw new Error('This wrapper accepts only Vite build --mode production');
  }
  const require = createRequire(resolve(root, 'package.json'));
  const packagePath = require.resolve('vite/package.json');
  const bin = JSON.parse(readFileSync(packagePath, 'utf8')).bin.vite;
  if (typeof bin !== 'string') throw new Error('Locked Vite CLI is missing');
  return [process.execPath, ['--max-old-space-size=6144', resolve(dirname(packagePath), bin), ...args]];
}

export async function runVite(root, args) {
  if (process.platform !== 'linux' || process.env.JRC_VITE_BUILD_HEAP_MIB !== '6144') {
    throw new Error('Explicit Linux frontend heap configuration required');
  }
  const initial = sampleResources(root);
  const reason = resourceReason(initial, true);
  if (reason) throw new Error(reason);
  const [executable, argv] = viteCommand(root, args);
  const child = spawn(executable, argv, { cwd: root, env: process.env, stdio: 'inherit' });
  let failure = null;
  let killTimer;
  let minimumMemory = initial.availableMemory;
  let minimumDisk = initial.diskFree;
  const stop = why => {
    if (failure) return;
    failure = why;
    // The ChildProcess handle belongs only to the Vite started above.
    child.kill('SIGTERM');
    killTimer = setTimeout(() => child.kill('SIGKILL'), 10_000);
    killTimer.unref();
  };
  const interval = setInterval(() => {
    try {
      const sample = sampleResources(root);
      minimumMemory = Math.min(minimumMemory, sample.availableMemory);
      minimumDisk = Math.min(minimumDisk, sample.diskFree);
      const reason = resourceReason(sample);
      if (reason) stop(reason);
    } catch {
      stop('resource_measurement_failed');
    }
  }, 500);
  const terminate = () => stop('termination_requested');
  const interrupt = () => stop('interrupt_requested');
  process.on('SIGTERM', terminate);
  process.on('SIGINT', interrupt);
  console.log(JSON.stringify({ component: 'jrc_vite_heap', heapMiB: LIMITS.heapMiB, initial, vitePid: child.pid }));
  return new Promise(resolveResult => {
    let settled = false;
    const finish = (code, signal, error) => {
      if (settled) return;
      settled = true;
      clearInterval(interval);
      clearTimeout(killTimer);
      process.removeListener('SIGTERM', terminate);
      process.removeListener('SIGINT', interrupt);
      const passed = code === 0 && !failure && !error;
      console.log(JSON.stringify({ component: 'jrc_vite_heap', passed, code, signal,
        reason: failure || (error ? 'vite_spawn_failed' : null), minimumMemory, minimumDisk }));
      resolveResult(passed ? 0 : 1);
    };
    child.once('error', error => finish(null, null, error));
    child.once('exit', (code, signal) => finish(code, signal, null));
  });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
  runVite(root, process.argv.slice(2)).then(code => {
    process.exitCode = code;
  }).catch(error => {
    console.error(JSON.stringify({ component: 'jrc_vite_heap', passed: false, reason: error.message }));
    process.exitCode = 1;
  });
}
