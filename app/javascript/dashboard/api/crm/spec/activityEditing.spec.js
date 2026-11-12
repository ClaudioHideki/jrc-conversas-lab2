import activitiesAPI from '../activities';

describe('Captured account native activity editor API', () => {
  beforeEach(() => {
    vi.stubGlobal('axios', { get: vi.fn(), patch: vi.fn() });
    window.history.replaceState({}, '', '/app/accounts/99/crm/activities');
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    window.history.replaceState({}, '', '/');
  });
  it('retains the captured account for read and update even after the browser route changes', () => {
    const controller = new AbortController();
    const options = { signal: controller.signal };
    const body = {
      expected_version: 'exact-source-version',
      activity: { title: 'Revised' },
    };
    activitiesAPI.showInAccount('17', 9, options);
    activitiesAPI.updateInAccount('17', 9, body, options);
    expect(window.axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/17/crm/activities/9',
      options
    );
    expect(window.axios.patch).toHaveBeenCalledWith(
      '/api/v1/accounts/17/crm/activities/9',
      body,
      options
    );
  });
  it('rejects invalid account identities before any request', () => {
    expect(() => activitiesAPI.showInAccount('../99', 9)).toThrow(
      'Invalid account context'
    );
    expect(window.axios.get).not.toHaveBeenCalled();
  });
});
