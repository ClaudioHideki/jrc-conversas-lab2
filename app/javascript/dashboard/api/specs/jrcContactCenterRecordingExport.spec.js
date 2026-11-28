import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import API from '../jrcContactCenter';

describe('Native recording metadata export HTTP transport', () => {
  const get = vi.fn();
  beforeEach(() => {
    get.mockReset();
    get.mockResolvedValue({ data: {} });
    vi.stubGlobal('axios', { get });
  });
  afterEach(() => vi.unstubAllGlobals());

  it('uses the native authenticated blob request with exact applied filters and its own abort signal', async () => {
    const signal = new AbortController().signal;
    const criteria = {
      from: '2026-11-20',
      to: '2026-11-26',
      unit_id: '11',
      direction: 'inbound',
      status: 'answered',
    };
    await API.exportRecordingsReport('1', criteria, signal);
    expect(get).toHaveBeenCalledExactlyOnceWith(
      '/api/v1/accounts/1/jrc_contact_center/reports/recordings/export',
      { params: criteria, signal, responseType: 'blob' }
    );
  });

  it('does not silently discard malformed scope filters before the server can reject them', async () => {
    const criteria = { unit_id: false, queue_id: ['11'] };
    await API.exportRecordingsReport('1', criteria);
    expect(get).toHaveBeenCalledExactlyOnceWith(
      '/api/v1/accounts/1/jrc_contact_center/reports/recordings/export',
      { params: criteria, signal: undefined, responseType: 'blob' }
    );
  });
});
