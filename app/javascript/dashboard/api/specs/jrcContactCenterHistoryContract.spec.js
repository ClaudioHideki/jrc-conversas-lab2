import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import API from '../jrcContactCenter';

describe('Native ending history HTTP contract transport', () => {
  const get = vi.fn();
  beforeEach(() => {
    get.mockReset();
    get.mockResolvedValue({ data: {} });
    vi.stubGlobal('axios', { get });
  });
  afterEach(() => vi.unstubAllGlobals());

  it('preserves the old default page request without enabling another contract', async () => {
    await API.endingAttemptHistory('1', '7');
    expect(get).toHaveBeenCalledExactlyOnceWith(
      '/api/v1/accounts/1/jrc_contact_center/qualifications/7/ending_attempts',
      { params: { page: 1 } }
    );
  });

  it('forwards the explicit new read contract and page but never caller-selected authority IDs', async () => {
    await API.endingAttemptHistory('1', '7', {
      page: 2,
      history_contract: 2,
      account_id: '999',
      user_id: '999',
      unit_id: '999',
    });
    expect(get).toHaveBeenCalledExactlyOnceWith(
      '/api/v1/accounts/1/jrc_contact_center/qualifications/7/ending_attempts',
      { params: { page: 2, history_contract: 2 } }
    );
  });
});
