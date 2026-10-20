import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { createStore } from 'vuex';
import ConnectionsPage from 'dashboard/routes/dashboard/jrcBroker/ConnectionsPage.vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { createJrcBrokerApi } from 'dashboard/api/jrcBroker';

vi.mock('dashboard/composables/useAccount', () => ({ useAccount: vi.fn() }));
vi.mock('dashboard/api/jrcBroker', () => ({ createJrcBrokerApi: vi.fn() }));

let wrapper;
let accountId;
let currentAccount;
let api;
let store;
let role;
beforeEach(() => {
  accountId = ref(1);
  currentAccount = ref({ features: { jrc_broker: true } });
  useAccount.mockReturnValue({ accountId, currentAccount });
  window.chatwootConfig = { jrcBrokerEnabled: true };
  role = ref('agent');
  store = createStore({
    getters: { getCurrentRole: () => role.value },
    mutations: { LOGOUT: () => {} },
  });
  api = {
    assignmentPolicy: vi
      .fn()
      .mockResolvedValue({ enabled: false, max_open: 10, inbox_ids: [] }),
    inboxes: vi.fn().mockResolvedValue([
      { id: 7, name: 'Support', jrc_broker_bound: true },
      { id: 8, name: 'Sales', jrc_broker_bound: true },
      {
        id: 9,
        name: 'Other API inbox',
        additional_attributes: { jrc_broker: true },
      },
    ]),
    status: vi.fn().mockResolvedValue({
      integrationStatus: 'READY',
      instanceStatus: 'DISCONNECTED',
      transportStatus: 'UNVERIFIED',
      allowedActions: ['status', 'pair'],
    }),
    pair: vi.fn().mockResolvedValue({
      action: {
        type: 'PAIRING_CODE',
        code: 'SYNTHETIC-QR',
        expiresAt: new Date(Date.now() + 60000).toISOString(),
      },
    }),
  };
  createJrcBrokerApi.mockReturnValue(api);
});

it('shows distribution settings only to an administrator, without enabling them', async () => {
  role.value = 'administrator';
  wrapper = mount(ConnectionsPage, { global: { plugins: [store] } });
  await flushPromises();
  expect(api.assignmentPolicy).toHaveBeenCalledOnce();
  expect(wrapper.find('input[type="checkbox"]').exists()).toBe(true);
  role.value = 'agent';
  await flushPromises();
  expect(wrapper.find('input[type="checkbox"]').exists()).toBe(false);
});
afterEach(() => {
  wrapper?.unmount();
  delete window.chatwootConfig;
});

it('connects an assigned bound inbox without any conversation, and clears pairing when switching inbox', async () => {
  wrapper = mount(ConnectionsPage, { global: { plugins: [store] } });
  await flushPromises();
  expect(wrapper.findAll('option').map(option => option.text())).toEqual([
    'Support',
    'Sales',
  ]);
  expect(api.pair).not.toHaveBeenCalled();
  expect(api.status).toHaveBeenCalledWith(7, expect.any(AbortSignal));
  await wrapper.get('[data-testid="pair"]').trigger('click');
  await flushPromises();
  expect(wrapper.text()).toContain('SYNTHETIC-QR');
  await wrapper.get('select').setValue('8');
  await flushPromises();
  expect(wrapper.text()).not.toContain('SYNTHETIC-QR');
  expect(api.status).toHaveBeenLastCalledWith(8, expect.any(AbortSignal));
});

it('discards an old account response while the new account is loading', async () => {
  let resolveOld;
  api.inboxes.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        resolveOld = resolve;
      })
  );
  wrapper = mount(ConnectionsPage, { global: { plugins: [store] } });
  const oldSignal = api.inboxes.mock.calls[0][0];
  accountId.value = 2;
  await flushPromises();
  resolveOld([{ id: 99, name: 'Previous account', jrc_broker_bound: true }]);
  await flushPromises();
  expect(oldSignal.aborted).toBe(true);
  expect(createJrcBrokerApi).toHaveBeenCalledWith(2);
  expect(wrapper.text()).not.toContain('Previous account');
  expect(api.status).not.toHaveBeenCalledWith(99, expect.anything());
});

it('hides connections and stops pending work on logout', async () => {
  wrapper = mount(ConnectionsPage, { global: { plugins: [store] } });
  await flushPromises();
  await wrapper.get('[data-testid="pair"]').trigger('click');
  await flushPromises();
  store.commit('LOGOUT');
  await flushPromises();
  expect(wrapper.find('select').exists()).toBe(false);
  expect(wrapper.text()).not.toContain('SYNTHETIC-QR');
  expect(api.inboxes.mock.calls[0][0].aborted).toBe(true);
});

it('does not load connections when the account feature is disabled, including direct navigation', async () => {
  currentAccount.value.features.jrc_broker = false;
  wrapper = mount(ConnectionsPage, { global: { plugins: [store] } });
  await flushPromises();
  expect(api.inboxes).not.toHaveBeenCalled();
  expect(api.status).not.toHaveBeenCalled();
  expect(wrapper.find('select').exists()).toBe(false);
});

it('shows an error rather than an empty inbox list on failure, and permits an explicit retry', async () => {
  api.inboxes.mockRejectedValueOnce({ response: { status: 503 } });
  wrapper = mount(ConnectionsPage, { global: { plugins: [store] } });
  await flushPromises();
  expect(wrapper.get('[role="alert"]').exists()).toBe(true);
  expect(wrapper.find('[data-testid="no-connections"]').exists()).toBe(false);
  await wrapper.get('[data-testid="refresh-connections"]').trigger('click');
  await flushPromises();
  expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  expect(wrapper.find('select').exists()).toBe(true);
});

it('keeps the page available with no conversations or bound inboxes and does not invent a QR', async () => {
  api.inboxes.mockResolvedValue([]);
  wrapper = mount(ConnectionsPage, { global: { plugins: [store] } });
  await flushPromises();
  expect(wrapper.get('[data-testid="no-connections"]').exists()).toBe(true);
  expect(api.status).not.toHaveBeenCalled();
  expect(api.pair).not.toHaveBeenCalled();
});

it('does not expose pairing to an agent whose server permissions only allow status', async () => {
  api.status.mockResolvedValue({
    integrationStatus: 'READY',
    instanceStatus: 'DISCONNECTED',
    transportStatus: 'UNVERIFIED',
    allowedActions: ['status'],
  });
  wrapper = mount(ConnectionsPage, { global: { plugins: [store] } });
  await flushPromises();
  expect(wrapper.find('[data-testid="pair"]').exists()).toBe(false);
  expect(api.pair).not.toHaveBeenCalled();
});
