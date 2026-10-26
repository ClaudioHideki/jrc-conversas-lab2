import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { login, PortalError, request, submission, upload } from './client';

describe('Requester portal native session client', () => {
  beforeEach(() => {
    document.head.innerHTML = '<meta name="csrf-token" content="native-csrf">';
    vi.stubGlobal('fetch', vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
    document.head.innerHTML = '';
  });

  it('sends cookie-bound requests with CSRF and disables browser response caching', async () => {
    fetch.mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ context: { id: '7' } }),
    });
    await expect(
      request('/portal/session', { method: 'PATCH', body: { context_id: '7' } })
    ).resolves.toEqual({ context: { id: '7' } });
    expect(fetch).toHaveBeenCalledWith(
      '/portal/session',
      expect.objectContaining({
        method: 'PATCH',
        credentials: 'same-origin',
        cache: 'no-store',
        body: JSON.stringify({ context_id: '7' }),
        headers: {
          Accept: 'application/json',
          'Content-Type': 'application/json',
          'X-CSRF-Token': 'native-csrf',
        },
      })
    );
  });

  it('lets the browser set the multipart boundary for public files', async () => {
    const file = new File(['public'], 'evidence.txt', {
      type: 'text/plain',
      lastModified: 10,
    });
    const body = upload({ ticket: { service_id: '12' } }, [file]);
    fetch.mockResolvedValue({ ok: true, status: 204 });
    await expect(
      request('/portal/api/chamados', { method: 'POST', body })
    ).resolves.toEqual({});
    expect(body.get('ticket')).toBe('{"service_id":"12"}');
    expect(body.getAll('files[]')).toEqual([file]);
    expect(fetch.mock.calls[0][1].headers).not.toHaveProperty('Content-Type');
  });

  it('preserves denied and scan-blocked server errors without treating them as downloads', async () => {
    fetch.mockResolvedValue({
      ok: false,
      status: 409,
      json: async () => ({ code: 'attachment_scan_unavailable' }),
    });
    await expect(request('/portal/file', { blob: true })).rejects.toMatchObject(
      {
        status: 409,
        code: 'attachment_scan_unavailable',
      }
    );
    fetch.mockResolvedValue({
      ok: false,
      status: 403,
      json: async () => {
        throw new Error('not JSON');
      },
    });
    await expect(request('/portal/session')).rejects.toMatchObject({
      status: 403,
      code: 'request_failed',
    });
  });

  it('returns an authenticated file body without an object-storage redirect', async () => {
    const file = new Blob(['public evidence']);
    fetch.mockResolvedValue({ ok: true, status: 200, blob: async () => file });
    await expect(request('/portal/file', { blob: true })).resolves.toBe(file);
  });

  it.each([
    { mfa_required: true, mfa_token: 'native-mfa-challenge' },
    { sessions_limit_reached: true, sessions: [{ id: 'existing-session' }] },
  ])(
    'does not create a cookie bridge before native verification completes: %j',
    async payload => {
      fetch.mockResolvedValue({ ok: false, json: async () => payload });
      await expect(
        login({ email: 'requester@example.test', password: 'native-password' })
      ).resolves.toEqual(payload);
      expect(fetch).toHaveBeenCalledTimes(1);
      expect(fetch.mock.calls[0][0]).toBe('/auth/sign_in');
    }
  );

  it('bridges only the native response headers and never persists credentials in web storage', async () => {
    const localStorageWrite = vi.spyOn(Storage.prototype, 'setItem');
    const credentials = {
      'access-token': 'native-token',
      client: 'native-client',
      uid: 'requester@example.test',
      expiry: '2000000000',
      'token-type': 'Bearer',
    };
    fetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ data: {} }),
      headers: new Headers(credentials),
    });
    fetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({ contexts: [] }),
    });
    await login({ email: credentials.uid, password: 'native-password' });
    expect(fetch.mock.calls[1]).toEqual([
      '/portal/session',
      expect.objectContaining({
        method: 'POST',
        credentials: 'same-origin',
        headers: expect.objectContaining(credentials),
      }),
    ]);
    expect(fetch.mock.calls[1][1]).not.toHaveProperty('body');
    expect(localStorageWrite).not.toHaveBeenCalled();
  });

  it('keeps the same idempotency key after a retry and requires a new intention after editing', () => {
    vi.spyOn(crypto, 'randomUUID')
      .mockReturnValueOnce('first-request')
      .mockReturnValueOnce('edited-request');
    const intention = submission();
    const fields = { title: 'Customer request', service_id: '12' };
    const file = new File(['evidence'], 'evidence.txt', { lastModified: 10 });
    expect(intention.key(fields, [file])).toBe('first-request');
    expect(intention.key({ ...fields }, [file])).toBe('first-request');
    expect(() =>
      intention.key({ ...fields, title: 'Changed' }, [file])
    ).toThrow(PortalError);
    expect(() =>
      intention.key(fields, [
        new File(['changed evidence'], 'evidence.txt', { lastModified: 11 }),
      ])
    ).toThrow(PortalError);
    intention.reset();
    expect(intention.key({ ...fields, title: 'Changed' }, [file])).toBe(
      'edited-request'
    );
  });

  it('only releases a rejected intention when no earlier request had an uncertain outcome', () => {
    const fields = { title: 'Public request' };
    const rejected = submission();
    rejected.key(fields, []);
    rejected.failed(new PortalError(422, 'invalid_input'));
    expect(() =>
      rejected.key({ title: 'Corrected request' }, [])
    ).not.toThrow();
    const uncertain = submission();
    const originalKey = uncertain.key(fields, []);
    uncertain.failed(new TypeError('Connection interrupted'));
    uncertain.failed(new PortalError(404, 'not_found'));
    expect(uncertain.key(fields, [])).toBe(originalKey);
    expect(() => uncertain.key({ title: 'Changed request' }, [])).toThrow(
      PortalError
    );
  });
});
