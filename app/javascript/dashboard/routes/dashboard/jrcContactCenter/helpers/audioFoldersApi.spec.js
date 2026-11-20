import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import API from 'dashboard/api/jrcContactCenter';

let http;
beforeEach(() => {
  http = { get: vi.fn(), patch: vi.fn(), post: vi.fn() };
  vi.stubGlobal('axios', http);
});
afterEach(() => vi.unstubAllGlobals());

describe('native unit scoped institutional folder transport', () => {
  it('preserves explicit pagination, search and native unit without authorizing them on the client', () => {
    const query = {
      unit_id: '10',
      parent_id: '7',
      q: 'SYNTHETIC',
      page: 2,
      per_page: 20,
    };
    API.audioFolders('1', query);
    expect(http.get).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/audio_folders',
      { params: query }
    );
  });

  it('creates only metadata and uses the same native endpoint for revision conflict readback', () => {
    const folder = { unit_id: '10', name: 'SYNTHETIC', parent_id: null };
    API.saveAudioFolder('1', undefined, folder);
    API.configurationRecord('1', 'audio_folders', '9007199254740993');
    expect(http.post).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/audio_folders',
      { folder }
    );
    expect(http.get).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/audio_folders/9007199254740993'
    );
  });

  it('preserves the full bigint identity and expected revision on a metadata update', () => {
    const folder = { name: 'SYNTHETIC moved', parent_id: '11' };
    API.saveAudioFolder('1', '9007199254740993', folder, {
      expected_revision: 'synthetic-revision',
    });
    expect(http.patch).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/audio_folders/9007199254740993',
      {
        folder,
        expected_revision: 'synthetic-revision',
      }
    );
    expect(http.post).not.toHaveBeenCalled();
  });

  it.each([
    0,
    '',
    false,
    '../commands',
    '1\n',
    '9223372036854775808',
    Number.MAX_SAFE_INTEGER + 1,
  ])(
    'refuses unsafe or missing update identity %s without silently creating a root',
    id => {
      expect(() =>
        API.saveAudioFolder('1', id, { name: 'SYNTHETIC' })
      ).toThrow();
      expect(http.post).not.toHaveBeenCalled();
      expect(http.patch).not.toHaveBeenCalled();
    }
  );
});
