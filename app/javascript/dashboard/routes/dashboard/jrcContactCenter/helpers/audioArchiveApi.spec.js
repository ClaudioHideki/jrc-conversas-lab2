import { afterEach, describe, expect, it, vi } from 'vitest';
import API from 'dashboard/api/jrcContactCenter';

afterEach(() => vi.unstubAllGlobals());
describe('native selected audio ZIP transport', () => {
  it('requests one bounded blob response with only the reviewed source identities', () => {
    const http = { post: vi.fn() };
    vi.stubGlobal('axios', http);
    const items = [
      {
        audio_asset_id: '9223372036854775806',
        audio_version_id: '9223372036854775807',
        inspection_id: '100',
        sha256: 'a'.repeat(64),
      },
    ];
    API.audioArchive('1', items);
    expect(http.post).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/audio_archives',
      { items },
      { responseType: 'blob', timeout: 30000 }
    );
  });
});
