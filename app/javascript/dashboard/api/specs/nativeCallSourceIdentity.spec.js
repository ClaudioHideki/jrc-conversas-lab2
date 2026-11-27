import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import API from '../jrcContactCenter';

const get = vi.fn();
beforeEach(() => {
  get.mockReset();
  get.mockResolvedValue({ data: {} });
  vi.stubGlobal('axios', { get });
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
