import assert from 'node:assert/strict';
import test from 'node:test';
import { proveOwnedMediaFailure } from './call-center-owned-media-failure.mjs';

// Procedure regressions only; actual native media/browser/UI acceptance remains mandatory in Chrome.
const fixture = ({ trusted = true, emitError = true } = {}) => {
  const calls = [];
  const listeners = new Map();
  const audio = {
    currentSrc: 'blob:authorized-already-loaded',
    readyState: 4,
    networkState: 1,
    error: null,
    addEventListener: (name, callback) => listeners.set(name, callback),
    removeEventListener: name => listeners.delete(name),
    set src(value) {
      calls.push(['src', value]);
    },
    load() {
      calls.push(['load']);
      if (emitError) {
        this.error = { code: 4 };
        listeners.get('error')({ isTrusted: trusted });
      }
    },
  };
  return { audio, calls, listeners };
};

test('copies the actual authorized bytes and revokes a previously unused URL before loading it', async t => {
  const { audio, calls } = fixture();
  const bytes = new Blob(['SYNTHETIC procedure bytes'], { type: 'audio/wav' });
  t.mock.method(global, 'fetch', async value => {
    assert.equal(value, audio.currentSrc);
    calls.push(['fetch', value]);
    return { ok: true, blob: async () => bytes };
  });
  t.mock.method(URL, 'createObjectURL', value => {
    assert.equal(value, bytes);
    calls.push(['create']);
    return 'blob:unused-owned-copy';
  });
  t.mock.method(URL, 'revokeObjectURL', value => calls.push(['revoke', value]));
  const result = await proveOwnedMediaFailure(audio);
  assert.deepEqual(calls, [
    ['fetch', audio.currentSrc],
    ['create'],
    ['revoke', 'blob:unused-owned-copy'],
    ['src', 'blob:unused-owned-copy'],
    ['load'],
  ]);
  assert.equal(result.actual_authorized_audio_bytes, bytes.size);
  assert.equal(result.code, 4);
  assert.equal(result.trusted_browser_event, true);
  assert.equal(result.revoked_before_first_load, true);
});

test('refuses an external source without fetching or changing the media', async t => {
  const { audio, calls } = fixture();
  audio.currentSrc = 'https://invalid.example/never-requested';
  const fetcher = t.mock.method(global, 'fetch', () => {
    throw new Error('Unexpected fetch');
  });
  await assert.rejects(
    proveOwnedMediaFailure(audio),
    /owned browser media blob/
  );
  assert.equal(fetcher.mock.callCount(), 0);
  assert.deepEqual(calls, []);
});

test('rejects unreadable and empty source bytes instead of manufacturing a successful failure proof', async t => {
  const { audio, calls } = fixture();
  let count = 0;
  t.mock.method(global, 'fetch', async () => {
    count += 1;
    return count === 1
      ? { ok: false }
      : { ok: true, blob: async () => new Blob([], { type: 'audio/wav' }) };
  });
  await assert.rejects(proveOwnedMediaFailure(audio), /could not be copied/);
  await assert.rejects(
    proveOwnedMediaFailure(audio),
    /nonempty authorized audio/
  );
  assert.deepEqual(calls, []);
});

test('fails on a missing or untrusted event and never fabricates an error event or a passing timeout', async t => {
  t.mock.method(global, 'fetch', async () => ({
    ok: true,
    blob: async () => new Blob(['SYNTHETIC'], { type: 'audio/wav' }),
  }));
  t.mock.method(URL, 'createObjectURL', () => 'blob:unused-owned-copy');
  t.mock.method(URL, 'revokeObjectURL', () => {});
  const absent = fixture({ emitError: false });
  await assert.rejects(
    proveOwnedMediaFailure(absent.audio, 8),
    /Native media failure not observed/
  );
  assert.equal(absent.listeners.size, 0);
  const untrusted = fixture({ trusted: false });
  await assert.rejects(
    proveOwnedMediaFailure(untrusted.audio),
    /actual trusted browser media failure/
  );
});
