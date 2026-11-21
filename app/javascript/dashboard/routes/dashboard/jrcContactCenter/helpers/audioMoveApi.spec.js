import { afterEach, describe, expect, it, vi } from 'vitest';
import API from 'dashboard/api/jrcContactCenter';

afterEach(() => vi.unstubAllGlobals());
describe('native selected audio metadata move transport', () => {
  it('posts exact reviewed string identities without converting bigint values or adding actor authority', () => {
    const http = { post: vi.fn() };
    vi.stubGlobal('axios', http);
    const body = {
      unit_id: '10',
      folder_id: null,
      items: [
        {
          audio_asset_id: '9223372036854775807',
          expected_revision: 'a'.repeat(64),
        },
      ],
    };
    API.moveAudioAssets('1', body);
    expect(http.post).toHaveBeenCalledExactlyOnceWith(
      '/api/v1/accounts/1/jrc_contact_center/audio_asset_moves',
      body
    );
    expect(body.items[0].audio_asset_id).toBe('9223372036854775807');
  });
});
