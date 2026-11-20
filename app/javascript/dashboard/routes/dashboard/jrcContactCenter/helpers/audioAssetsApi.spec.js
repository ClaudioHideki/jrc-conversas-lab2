import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import API from 'dashboard/api/jrcContactCenter';

beforeEach(() => {
  vi.stubGlobal('axios', { get: vi.fn(), post: vi.fn(), patch: vi.fn() });
});
afterEach(() => {
  vi.unstubAllGlobals();
});

describe('private audio metadata and actual multipart API contract', () => {
  it('fetches exact-version bytes using native authorization headers rather than a signed storage URL', () => {
    API.audioBytes('1', '9007199254740993', '9007199254740994');
    expect(global.axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/audio_assets/9007199254740993/versions/9007199254740994/bytes',
      { responseType: 'blob', timeout: 30000 }
    );
  });
  it('passes bounded native unit, folder and pagination filters without accepting them as authentication', () => {
    const params = {
      unit_id: '10',
      folder_id: '9007199254740993',
      page: 2,
      per_page: 5,
    };
    API.audioAssets('1', params);
    expect(global.axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/audio_assets',
      { params }
    );
  });

  it('preserves full PostgreSQL identifiers in asset details, immutable history and CAS reload', () => {
    const id = '9007199254740993';
    const base = `/api/v1/accounts/1/jrc_contact_center/audio_assets/${id}`;
    API.audioAsset('1', id);
    API.audioVersions('1', id, { page: 2 });
    API.configurationRecord('1', 'audio_assets', id);
    expect(global.axios.get.mock.calls).toEqual([
      [base],
      [`${base}/versions`, { params: { page: 2 } }],
      [base],
    ]);
  });

  it('leaves the multipart boundary to the browser and reuses the submitted exact body for replacement', () => {
    const body = new FormData();
    body.append('idempotency_key', 'SYNTHETIC-native-key');
    API.receiveAudioAsset('1', body);
    API.receiveAudioVersion('1', '44', body);
    expect(global.axios.post.mock.calls).toEqual([
      ['/api/v1/accounts/1/jrc_contact_center/audio_assets', body],
      ['/api/v1/accounts/1/jrc_contact_center/audio_assets/44/versions', body],
    ]);
  });

  it('submits reviewed metadata and native CAS without a caller-provided actor or account grant', () => {
    const draft = { name: 'SYNTHETIC audio', folder_id: '10' };
    API.updateAudioAsset('1', '44', draft, {
      expected_revision: 'a'.repeat(64),
    });
    expect(global.axios.patch).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/audio_assets/44',
      { asset: draft, expected_revision: 'a'.repeat(64) }
    );
  });

  it.each([false, '0', '1/../../2', '9223372036854775808', 9007199254740992])(
    'rejects malformed asset locator %s before making a request',
    id => {
      expect(() => API.audioAsset('1', id)).toThrow();
      expect(() => API.receiveAudioVersion('1', id, new FormData())).toThrow();
      expect(() => API.audioBytes('1', id, '99')).toThrow();
      expect(() => API.audioBytes('1', '44', id)).toThrow();
      expect(global.axios.get).not.toHaveBeenCalled();
      expect(global.axios.post).not.toHaveBeenCalled();
    }
  );
});
