import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { API, removeHeader, setHeader } from 'widget/helpers/axios';
import { getProtectedAttachment } from '../messageAttachments';

beforeEach(() => {
  setHeader('native-visitor-jwt');
  vi.spyOn(API, 'get').mockResolvedValue({ data: new Blob(['evidence']) });
});

afterEach(() => {
  removeHeader('X-Auth-Token');
  vi.restoreAllMocks();
});

describe('native widget protected attachment transport', () => {
  it('uses a fixed native route and the existing axios identity without putting it in the URL', async () => {
    const controller = new AbortController();
    await getProtectedAttachment({
      messageId: 12,
      attachmentId: 34,
      websiteToken: 'widget-token',
      signal: controller.signal,
      data_url: 'https://untrusted.example/steal-jwt',
    });
    expect(API.get).toHaveBeenCalledExactlyOnceWith(
      '/api/v1/widget/messages/12/attachments/34',
      {
        params: { website_token: 'widget-token' },
        responseType: 'blob',
        signal: controller.signal,
        timeout: 20000,
      }
    );
    expect(API.defaults.headers.common['X-Auth-Token']).toBe(
      'native-visitor-jwt'
    );
    expect(JSON.stringify(API.get.mock.calls)).not.toContain(
      'native-visitor-jwt'
    );
    expect(JSON.stringify(API.get.mock.calls)).not.toContain('untrusted');
  });

  it.each(['https://untrusted.example/1', '../1', '1?token=x', 0, -1])(
    'rejects a route identifier %s before calling the authenticated client',
    messageId => {
      expect(() =>
        getProtectedAttachment({
          messageId,
          attachmentId: 34,
          websiteToken: 'widget-token',
        })
      ).toThrow('Invalid attachment identifier');
      expect(API.get).not.toHaveBeenCalled();
    }
  );
});
