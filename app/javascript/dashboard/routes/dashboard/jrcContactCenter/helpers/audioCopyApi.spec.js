import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import API from 'dashboard/api/jrcContactCenter';

let http;
beforeEach(() => {
  http = { post: vi.fn() };
  vi.stubGlobal('axios', http);
});
afterEach(() => vi.unstubAllGlobals());

describe('native institutional audio copy transport', () => {
  it('preserves canonical bigint identity and the reviewed body without multipart or an authority override', () => {
    const body = {
      asset: { name: 'SYNTHETIC copy' },
      source_version_id: '9007199254740995',
      expected_revision: 'a'.repeat(64),
      idempotency_key: 'synthetic-reviewed-copy-0001',
    };
    API.duplicateAudioAsset('1', '9007199254740993', body);
    expect(http.post).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/audio_assets/9007199254740993/duplicate',
      body
    );
  });
  it.each(['../commands', '4\n', Number.MAX_SAFE_INTEGER + 1])(
    'rejects unsafe asset identity %s before transport',
    value => {
      expect(() => API.duplicateAudioAsset('1', value, {})).toThrow();
      expect(http.post).not.toHaveBeenCalled();
    }
  );
});
