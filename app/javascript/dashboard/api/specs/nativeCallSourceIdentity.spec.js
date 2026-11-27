import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import API from '../jrcContactCenter';

const get = vi.fn();
const post = vi.fn();
beforeEach(() => {
  get.mockReset();
  get.mockResolvedValue({ data: {} });
  post.mockReset().mockResolvedValue({ data: {} });
  vi.stubGlobal('axios', { get, post });
});
afterEach(() => vi.unstubAllGlobals());

describe('native call context identity without Number rounding', () => {
  it('preserves a native bigint call-session ID as an exact path segment', async () => {
    await API.call('1', '9007199254740993');
    expect(get).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/call_sessions/9007199254740993'
    );
  });

  it('preserves the existing safe numeric call API contract', async () => {
    await API.call(1, 7);
    expect(get).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/call_sessions/7'
    );
  });

  it('rejects malformed, out-of-range or already rounded identities before any request', () => {
    [
      '../7',
      '7\n',
      '0',
      '9223372036854775808',
      Number.MAX_SAFE_INTEGER + 1,
    ].forEach(id => {
      expect(() => API.call('1', id)).toThrow('Invalid local record identity');
    });
    expect(get).not.toHaveBeenCalled();
  });
});

describe('native initial recording customer-link paths', () => {
  it('preserves the exact recording identity and abort signal in the native preview', async () => {
    const controller = new AbortController();
    await API.recordingCustomerLink('1', '9007199254740993', {
      signal: controller.signal,
    });
    expect(get).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/recordings/9007199254740993/customer_link',
      {
        signal: controller.signal,
        timeout: 20000,
      }
    );
    expect(post).not.toHaveBeenCalled();
  });
  it('preserves the exact recording identity and sends only the explicit native link payload', async () => {
    const input = {
      contact_id: '33',
      call_session_id: '9',
      call_id: 'SYNTHETIC link',
      lock_version: 0,
      confirm: true,
    };
    await API.linkRecordingCustomer('1', '9007199254740993', input);
    expect(post).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/recordings/9007199254740993/customer_link',
      {
        customer_link: input,
      },
      { timeout: 20000 }
    );
    expect(get).not.toHaveBeenCalled();
  });
  it.each(['recordingCustomerLink', 'linkRecordingCustomer'])(
    'rejects malformed source IDs for %s before any transport',
    method => {
      ['../7', '0', '9223372036854775808', Number.MAX_SAFE_INTEGER + 1].forEach(
        id => {
          expect(() => API[method]('1', id, {})).toThrow(
            'Invalid local record identity'
          );
        }
      );
      expect(get).not.toHaveBeenCalled();
      expect(post).not.toHaveBeenCalled();
    }
  );
});
