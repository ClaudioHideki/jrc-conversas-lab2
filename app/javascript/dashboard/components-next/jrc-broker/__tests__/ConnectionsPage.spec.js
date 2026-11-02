import { mount, flushPromises } from '@vue/test-utils';
import { defineComponent, h, ref } from 'vue';
import { createStore } from 'vuex';
import ConnectionsPage from 'dashboard/routes/dashboard/jrcBroker/ConnectionsPage.vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { createJrcBrokerApi } from 'dashboard/api/jrcBroker';

vi.mock('dashboard/composables/useAccount', () => ({ useAccount: vi.fn() }));
vi.mock('dashboard/api/jrcBroker', () => ({ createJrcBrokerApi: vi.fn() }));

const DialogStub = defineComponent({
  props: {
    title: { type: String, default: '' },
    useForm: { type: Boolean, default: true },
  },
  emits: ['close'],
  setup(props, { slots, expose, emit }) {
    const opened = ref(false);
    const close = () => {
      opened.value = false;
      emit('close');
    };
    expose({
      open: () => {
        opened.value = true;
      },
      close,
    });
    return () =>
      h(
        'div',
        opened.value ? { role: 'dialog', 'aria-label': props.title } : {},
        opened.value
          ? [
              h(
                'button',
                { 'data-testid': 'close-connection-dialog', onClick: close },
                'Close'
              ),
              h(props.useForm ? 'form' : 'div', slots.default?.()),
            ]
          : []
      );
  },
});

let store;
const mountPage = (options = {}) =>
  mount(ConnectionsPage, {
    ...options,
    global: {
      plugins: [store],
      stubs: { Dialog: DialogStub, RouterLink: true },
    },
  });

let wrapper;
let accountId;
let currentAccount;
let api;
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
    connectionDistribution: vi
      .fn()
      .mockResolvedValue({ policy: null, teams: [] }),
    saveConnectionDistribution: vi.fn(),
    distributionHistory: vi.fn().mockResolvedValue({ data: [] }),
    resources: vi.fn().mockResolvedValue({
      providers: [],
      instances: [
        {
          id: '11111111-1111-4111-8111-111111111111',
          name: 'Available connection',
        },
      ],
      agents: [],
      connections: [],
    }),
    operations: vi.fn().mockResolvedValue({ data: [] }),
    create: vi.fn(),
    operation: vi.fn(),
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
      observedNumberSuffix: '2000',
      checkedAt: '2026-11-02T12:00:00Z',
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
  wrapper = mountPage();
  await flushPromises();
  expect(api.assignmentPolicy).toHaveBeenCalledOnce();
  expect(wrapper.find('input[type="checkbox"]').exists()).toBe(true);
  role.value = 'agent';
  await flushPromises();
  expect(wrapper.find('input[type="checkbox"]').exists()).toBe(false);
});

it('offers accessible detail tabs without remounting health polling or fetching history automatically', async () => {
  role.value = 'administrator';
  wrapper = mountPage({ attachTo: document.body });
  await flushPromises();
  await wrapper.get('[data-testid="manage-connection-7"]').trigger('click');
  await flushPromises();
  const tabs = wrapper.findAll('[role="tab"]');
  expect(tabs.map(tab => tab.text())).toEqual([
    'Overview',
    'Distribution',
    'Distribution history',
    'Settings',
  ]);
  expect(tabs[0].attributes('aria-selected')).toBe('true');
  expect(tabs[0].attributes('tabindex')).toBe('0');
  const statusCalls = api.status.mock.calls.length;
  await tabs[0].trigger('keydown', { key: 'ArrowRight' });
  await flushPromises();
  expect(tabs[1].attributes('aria-selected')).toBe('true');
  expect(tabs[1].attributes('tabindex')).toBe('0');
  expect(document.activeElement).toBe(tabs[1].element);
  expect(wrapper.get('[role="tabpanel"]').attributes('aria-labelledby')).toBe(
    tabs[1].attributes('id')
  );
  expect(api.status).toHaveBeenCalledTimes(statusCalls);
  expect(api.connectionDistribution).toHaveBeenCalledTimes(1);
  expect(wrapper.get('[role="tabpanel"] form').exists()).toBe(true);
  expect(wrapper.find('[role="tabpanel"] form form').exists()).toBe(false);
  await tabs[2].trigger('click');
  expect(api.distributionHistory).not.toHaveBeenCalled();
  await wrapper
    .get('[data-testid="load-distribution-history"]')
    .trigger('click');
  await flushPromises();
  expect(api.distributionHistory).toHaveBeenCalledWith(
    7,
    expect.any(AbortSignal)
  );
  expect(wrapper.text()).toContain(
    'Connection and pairing events are not included'
  );
  role.value = 'agent';
  await flushPromises();
  expect(wrapper.findAll('[role="tab"]').map(tab => tab.text())).toEqual([
    'Overview',
    'Settings',
  ]);
  expect(wrapper.get('[role="tab"][aria-selected="true"]').text()).toBe(
    'Overview'
  );
});

it('updates the same card from real panel status and shows reconnection with saved distribution, not delivery success', async () => {
  role.value = 'administrator';
  api.connectionDistribution.mockResolvedValue({
    policy: { enabled: true, mode: 'direct', team_ids: [11], max_open: 6 },
    teams: [{ id: 11, name: 'Reception' }],
  });
  wrapper = mountPage();
  await flushPromises();
  const listRequests = api.inboxes.mock.calls.length;
  await wrapper.get('[data-testid="reconnect-connection-7"]').trigger('click');
  await flushPromises();
  api.status.mockResolvedValue({
    instanceStatus: 'CONNECTED',
    integrationStatus: 'READY',
    identityStatus: 'CONFIRMED',
    identityApproved: true,
    transportStatus: 'UNVERIFIED',
    allowedActions: ['status'],
  });
  await wrapper.get('[data-testid="pair"]').trigger('click');
  await flushPromises();
  expect(wrapper.get('[data-testid="connection-card-7"]').text()).toContain(
    'Connected'
  );
  expect(wrapper.find('[data-testid="reconnect-connection-7"]').exists()).toBe(
    false
  );
  expect(
    wrapper.get('[data-testid="reconnection-confirmation"]').text()
  ).toContain('WhatsApp session reconnected');
  expect(
    wrapper.get('[data-testid="reconnection-confirmation"]').text()
  ).toContain('does not confirm message delivery');
  expect(
    wrapper.get('[data-testid="distribution-saved-summary"]').text()
  ).toContain('Reception');
  expect(wrapper.get('[role="tab"][aria-selected="true"]').text()).toBe(
    'Overview'
  );
  expect(api.pair).toHaveBeenCalledTimes(1);
  expect(api.inboxes).toHaveBeenCalledTimes(listRequests);
});

it('presents the connection journey and detail tabs in Brazilian Portuguese', async () => {
  role.value = 'administrator';
  wrapper = mountPage();
  wrapper.vm.$i18n.locale = 'pt_BR';
  try {
    await flushPromises();
    expect(wrapper.get('h1').text()).toBe('Conexões WhatsApp');
    expect(wrapper.get('[data-testid="new-whatsapp-number"]').text()).toContain(
      'Conectar novo número'
    );
    await wrapper.get('[data-testid="manage-connection-7"]').trigger('click');
    await flushPromises();
    expect(wrapper.findAll('[role="tab"]').map(tab => tab.text())).toEqual([
      'Visão geral',
      'Distribuição',
      'Histórico de distribuição',
      'Configurações',
    ]);
    expect(wrapper.get('[data-testid="connection-health"]').text()).toContain(
      'Sessão do WhatsApp'
    );
    expect(wrapper.get('[data-testid="connection-health"]').text()).toContain(
      'Identidade do número'
    );
    expect(wrapper.text()).not.toContain('JRC_BROKER.DETAILS.');
  } finally {
    wrapper.vm.$i18n.locale = 'en';
  }
});

it('opens the existing new-number flow only on an explicit administrator action and refreshes after closing', async () => {
  role.value = 'administrator';
  wrapper = mountPage();
  await flushPromises();
  expect(api.resources).not.toHaveBeenCalled();
  expect(api.operations).not.toHaveBeenCalled();
  const open = wrapper.get('[data-testid="new-whatsapp-number"]');
  await open.trigger('click');
  await open.trigger('click');
  await flushPromises();
  expect(wrapper.findAll('[role="dialog"]')).toHaveLength(1);
  expect(wrapper.get('[role="dialog"]').attributes('aria-label')).toContain(
    'New WhatsApp number'
  );
  expect(api.resources).toHaveBeenCalledTimes(1);
  expect(api.operations).toHaveBeenCalledTimes(1);
  expect(api.create).not.toHaveBeenCalled();
  expect(wrapper.find('[role="dialog"] form form').exists()).toBe(false);
  const signal = api.resources.mock.calls[0][0];
  const listRequests = api.inboxes.mock.calls.length;
  await wrapper.get('[data-testid="close-connection-dialog"]').trigger('click');
  await flushPromises();
  expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
  expect(signal.aborted).toBe(true);
  expect(api.inboxes.mock.calls.length).toBeGreaterThan(listRequests);
  expect(api.create).not.toHaveBeenCalled();
});

it('hides new-number onboarding from agents and feature-disabled accounts', async () => {
  wrapper = mountPage();
  await flushPromises();
  expect(wrapper.find('[data-testid="new-whatsapp-number"]').exists()).toBe(
    false
  );
  role.value = 'administrator';
  currentAccount.value.features.jrc_broker = false;
  await flushPromises();
  expect(wrapper.find('[data-testid="new-whatsapp-number"]').exists()).toBe(
    false
  );
  expect(api.resources).not.toHaveBeenCalled();
  expect(api.create).not.toHaveBeenCalled();
});

it('keeps the existing flow single intent after an uncertain explicit submission', async () => {
  role.value = 'administrator';
  let rejectCreate;
  api.create.mockImplementation(
    () =>
      new Promise((_, reject) => {
        rejectCreate = reject;
      })
  );
  wrapper = mountPage();
  await flushPromises();
  await wrapper.get('[data-testid="new-whatsapp-number"]').trigger('click');
  await flushPromises();
  const form = wrapper.get('[role="dialog"] form');
  await form.get('input').setValue('Synthetic new number');
  await form
    .findAll('select')[1]
    .setValue('11111111-1111-4111-8111-111111111111');
  await form.trigger('submit');
  await form.trigger('submit');
  expect(api.create).toHaveBeenCalledTimes(1);
  const [body, key] = api.create.mock.calls[0];
  rejectCreate(new Error('synthetic timeout'));
  await flushPromises();
  expect(form.get('fieldset').element.disabled).toBe(true);
  await form.trigger('submit');
  expect(api.create).toHaveBeenCalledTimes(2);
  expect(api.create.mock.calls[1].slice(0, 2)).toEqual([body, key]);
  rejectCreate(new Error('synthetic timeout'));
  await flushPromises();
});

it('aborts new-number onboarding on an account switch and ignores old resources', async () => {
  role.value = 'administrator';
  let finishOld;
  api.resources.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finishOld = resolve;
      })
  );
  wrapper = mountPage();
  await flushPromises();
  await wrapper.get('[data-testid="new-whatsapp-number"]').trigger('click');
  await flushPromises();
  const oldSignal = api.resources.mock.calls[0][0];
  accountId.value = 2;
  await flushPromises();
  finishOld({
    providers: [],
    instances: [],
    agents: [],
    connections: [{ integrationId: 'old', name: 'Previous account resource' }],
  });
  await flushPromises();
  expect(oldSignal.aborted).toBe(true);
  expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
  expect(wrapper.text()).not.toContain('Previous account resource');
  expect(api.create).not.toHaveBeenCalled();
});

it.each(['logout', 'feature', 'role'])(
  'destroys new-number onboarding when access changes through %s',
  async change => {
    role.value = 'administrator';
    wrapper = mountPage();
    await flushPromises();
    await wrapper.get('[data-testid="new-whatsapp-number"]').trigger('click');
    await flushPromises();
    const signal = api.resources.mock.calls[0][0];
    if (change === 'logout') store.commit('LOGOUT');
    else if (change === 'feature')
      currentAccount.value.features.jrc_broker = false;
    else role.value = 'agent';
    await flushPromises();
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(signal.aborted).toBe(true);
    expect(api.create).not.toHaveBeenCalled();
  }
);

it('mounts per-connection distribution in the dialog only for an administrator', async () => {
  wrapper = mountPage();
  await flushPromises();
  await wrapper.get('[data-testid="manage-connection-7"]').trigger('click');
  await flushPromises();
  expect(api.connectionDistribution).not.toHaveBeenCalled();
  expect(
    wrapper.find('[data-testid="connection-distribution-policy"]').exists()
  ).toBe(false);
  role.value = 'administrator';
  await flushPromises();
  expect(
    wrapper
      .get('[role="dialog"] [data-testid="connection-distribution-policy"]')
      .exists()
  ).toBe(true);
  expect(api.connectionDistribution).toHaveBeenCalledWith(
    7,
    expect.any(AbortSignal)
  );
  expect(wrapper.find('[role="dialog"] form form').exists()).toBe(false);
  expect(api.saveConnectionDistribution).not.toHaveBeenCalled();
});
afterEach(() => {
  wrapper?.unmount();
  delete window.chatwootConfig;
});

it('lists authorized bound connections as cards without requesting a pairing code', async () => {
  wrapper = mountPage();
  await flushPromises();
  expect(wrapper.findAll('article').map(card => card.get('h2').text())).toEqual(
    ['Support', 'Sales']
  );
  expect(wrapper.find('select').exists()).toBe(false);
  expect(wrapper.text()).not.toContain('Other API inbox');
  expect(wrapper.get('[data-testid="connection-card-7"]').text()).toContain(
    '2000'
  );
  expect(
    wrapper.get('[data-testid="connection-card-7"] time').attributes('datetime')
  ).toBe('2026-11-02T12:00:00Z');
  expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
  expect(api.pair).not.toHaveBeenCalled();
  expect(api.status).toHaveBeenCalledWith(7, expect.any(AbortSignal));
  expect(api.status).toHaveBeenCalledWith(8, expect.any(AbortSignal));
});

it('reconnects the same inbox in a dialog and discards its QR when the dialog closes', async () => {
  wrapper = mountPage();
  await flushPromises();
  await wrapper.get('[data-testid="reconnect-connection-7"]').trigger('click');
  await flushPromises();
  expect(wrapper.get('[role="dialog"]').attributes('aria-label')).toContain(
    'Support'
  );
  expect(api.pair).not.toHaveBeenCalled();
  await wrapper.get('[data-testid="pair"]').trigger('click');
  await flushPromises();
  expect(api.pair).toHaveBeenCalledWith(
    7,
    expect.any(String),
    expect.any(AbortSignal)
  );
  expect(wrapper.text()).toContain('SYNTHETIC-QR');
  await wrapper.get('[data-testid="close-connection-dialog"]').trigger('click');
  await flushPromises();
  expect(wrapper.text()).not.toContain('SYNTHETIC-QR');
  expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
  await wrapper.get('[data-testid="manage-connection-8"]').trigger('click');
  await flushPromises();
  expect(api.status).toHaveBeenLastCalledWith(8, expect.any(AbortSignal));
  expect(wrapper.text()).not.toContain('SYNTHETIC-QR');
});

it('discards an old account response while the new account is loading', async () => {
  let resolveOld;
  api.inboxes.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        resolveOld = resolve;
      })
  );
  wrapper = mountPage();
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
  wrapper = mountPage();
  await flushPromises();
  await wrapper.get('[data-testid="reconnect-connection-7"]').trigger('click');
  await flushPromises();
  await wrapper.get('[data-testid="pair"]').trigger('click');
  await flushPromises();
  store.commit('LOGOUT');
  await flushPromises();
  expect(wrapper.find('article').exists()).toBe(false);
  expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
  expect(wrapper.text()).not.toContain('SYNTHETIC-QR');
  expect(api.inboxes.mock.calls[0][0].aborted).toBe(true);
});

it('does not load connections when the account feature is disabled, including direct navigation', async () => {
  currentAccount.value.features.jrc_broker = false;
  wrapper = mountPage();
  await flushPromises();
  expect(api.inboxes).not.toHaveBeenCalled();
  expect(api.status).not.toHaveBeenCalled();
  expect(wrapper.find('select').exists()).toBe(false);
});

it('shows an error rather than an empty inbox list on failure, and permits an explicit retry', async () => {
  api.inboxes.mockRejectedValueOnce({ response: { status: 503 } });
  wrapper = mountPage();
  await flushPromises();
  expect(wrapper.get('[role="alert"]').exists()).toBe(true);
  expect(wrapper.find('[data-testid="no-connections"]').exists()).toBe(false);
  await wrapper.get('[data-testid="refresh-connections"]').trigger('click');
  await flushPromises();
  expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  expect(wrapper.findAll('article')).toHaveLength(2);
});

it('keeps the page available with no conversations or bound inboxes and does not invent a QR', async () => {
  api.inboxes.mockResolvedValue([]);
  wrapper = mountPage();
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
  wrapper = mountPage();
  await flushPromises();
  expect(wrapper.find('[data-testid="reconnect-connection-7"]').exists()).toBe(
    false
  );
  await wrapper.get('[data-testid="manage-connection-7"]').trigger('click');
  await flushPromises();
  expect(wrapper.find('[data-testid="pair"]').exists()).toBe(false);
  expect(api.pair).not.toHaveBeenCalled();
});

it('checks access again when opening a previously authorized connection', async () => {
  wrapper = mountPage();
  await flushPromises();
  api.status.mockRejectedValueOnce({ response: { status: 403 } });
  await wrapper.get('[data-testid="reconnect-connection-7"]').trigger('click');
  await flushPromises();
  expect(wrapper.get('[role="dialog"] [role="alert"]').text()).toContain(
    'no longer available'
  );
  expect(wrapper.find('[data-testid="pair"]').exists()).toBe(false);
  expect(wrapper.text()).not.toContain('SYNTHETIC-QR');
  expect(api.pair).not.toHaveBeenCalled();
});

it('keeps failed status unknown instead of showing a disconnected or healthy connection', async () => {
  api.status.mockRejectedValue({ response: { status: 503 } });
  wrapper = mountPage();
  await flushPromises();
  const card = wrapper.get('[data-testid="connection-card-7"]');
  expect(card.find('[role="alert"]').exists()).toBe(true);
  expect(card.text()).not.toContain('Disconnected');
  expect(card.find('[data-testid="reconnect-connection-7"]').exists()).toBe(
    false
  );
  expect(card.find('time').exists()).toBe(false);
  expect(api.pair).not.toHaveBeenCalled();
});

it('removes a denied connection rather than leaving its details or reconnection available', async () => {
  api.status.mockImplementation(id =>
    id === 7
      ? Promise.reject(
          Object.assign(new Error('Forbidden'), { response: { status: 403 } })
        )
      : Promise.resolve({
          instanceStatus: 'CONNECTED',
          allowedActions: ['status'],
        })
  );
  wrapper = mountPage();
  await flushPromises();
  expect(wrapper.find('[data-testid="connection-card-7"]').exists()).toBe(
    false
  );
  expect(wrapper.get('[data-testid="connection-card-8"]').text()).toContain(
    'Connected'
  );
  expect(wrapper.text()).not.toContain('Support');
  expect(api.pair).not.toHaveBeenCalled();
});

it('ignores old connection health after switching account and closes the previous dialog', async () => {
  wrapper = mountPage();
  await flushPromises();
  await wrapper.get('[data-testid="manage-connection-7"]').trigger('click');
  await flushPromises();
  let finishOld;
  api.status.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finishOld = resolve;
      })
  );
  await wrapper.get('[data-testid="refresh-connections"]').trigger('click');
  await flushPromises();
  api.inboxes.mockResolvedValue([]);
  accountId.value = 2;
  await flushPromises();
  finishOld({
    instanceStatus: 'CONNECTED',
    observedNumberSuffix: '9999',
    allowedActions: ['status', 'pair'],
  });
  await flushPromises();
  expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
  expect(wrapper.text()).not.toContain('9999');
  expect(wrapper.find('[data-testid="connection-card-7"]').exists()).toBe(
    false
  );
});
