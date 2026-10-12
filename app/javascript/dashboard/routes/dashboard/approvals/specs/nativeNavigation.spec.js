import crm from 'dashboard/routes/dashboard/crm/crm.routes';
const mock = vi.hoisted(() => ({
  dispatch: vi.fn(),
  getters: {
    getCurrentUser: { accounts: [] },
    getCurrentAccount: {},
    'accounts/isFeatureEnabledonAccount': vi.fn(),
  },
}));
vi.mock('dashboard/store', () => ({ default: mock }));
describe('E4 commercial route context regression', () => {
  beforeEach(() => {
    mock.dispatch.mockResolvedValue();
    mock.getters['accounts/isFeatureEnabledonAccount'].mockReturnValue(true);
  });
  it('uses the target account profile on a cold route, without requiring a previously committed route', async () => {
    mock.getters.getCurrentAccount = {};
    mock.getters.getCurrentUser = {
      accounts: [{ id: 17, permissions: ['jrc_crm'] }],
    };
    const guard = crm.routes[0].beforeEnter;
    expect(await guard({ params: { accountId: '17' } })).toBe(true);
  });
  it('never borrows CRM permission from another current account', async () => {
    mock.getters.getCurrentAccount = { id: 18, permissions: ['jrc_crm'] };
    mock.getters.getCurrentUser = {
      accounts: [
        { id: 17, permissions: [] },
        { id: 18, permissions: ['jrc_crm'] },
      ],
    };
    expect(
      await crm.routes[0].beforeEnter({ params: { accountId: '17' } })
    ).toBe('/app/accounts/17/dashboard');
  });
  it('still denies a disabled commercial module', async () => {
    mock.getters.getCurrentUser = {
      accounts: [{ id: 17, permissions: ['jrc_crm'] }],
    };
    mock.getters['accounts/isFeatureEnabledonAccount'].mockReturnValue(false);
    expect(
      await crm.routes[0].beforeEnter({ params: { accountId: '17' } })
    ).toBe('/app/accounts/17/dashboard');
  });
});
