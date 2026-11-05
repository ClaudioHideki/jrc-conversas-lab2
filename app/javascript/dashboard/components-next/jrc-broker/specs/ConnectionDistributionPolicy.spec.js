import { mount, flushPromises } from '@vue/test-utils';
import ConnectionDistributionPolicy from '../ConnectionDistributionPolicy.vue';
import { createJrcBrokerApi } from 'dashboard/api/jrcBroker';

vi.mock('dashboard/api/jrcBroker', () => ({ createJrcBrokerApi: vi.fn() }));

const teams = [
  { id: 11, name: 'Reception' },
  { id: 22, name: 'Support' },
];
let wrapper;
let api;
const mountPolicy = () =>
  mount(ConnectionDistributionPolicy, {
    props: { accountId: 1, inboxId: 7 },
  });

beforeEach(() => {
  api = {
    connectionDistribution: vi.fn().mockResolvedValue({ policy: null, teams }),
    saveConnectionDistribution: vi
      .fn()
      .mockImplementation(async (_id, policy) => ({ policy })),
    distributionHistory: vi.fn().mockResolvedValue({ data: [] }),
  };
  createJrcBrokerApi.mockReturnValue(api);
});
afterEach(() => wrapper?.unmount());

it('configures exclusive visibility with a supervisor and an individual agent capacity', async () => {
  api.connectionDistribution.mockResolvedValue({
    policy: {
      enabled: true,
      mode: 'round_robin',
      team_ids: [11],
      max_open: 10,
    },
    teams,
    agents: [
      { id: 7, name: 'Supervisor' },
      { id: 8, name: 'Atendente' },
    ],
  });
  wrapper = mount(ConnectionDistributionPolicy, {
    props: { accountId: 1, inboxId: 7, presentation: 'policy' },
  });
  await flushPromises();
  expect(wrapper.find('[data-testid="distribution-visibility"]').exists()).toBe(
    true
  );
  await wrapper
    .get('[data-testid="distribution-visibility"]')
    .setValue('assigned_only');
  await wrapper.get('[data-supervisor-id="7"]').setValue(true);
  await wrapper.get('[data-agent-limit-id="8"]').setValue(5);
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(api.saveConnectionDistribution).toHaveBeenCalledWith(
    7,
    expect.objectContaining({
      visibility: 'assigned_only',
      supervisor_ids: [7],
      agent_limits: { 8: 5 },
    }),
    expect.any(AbortSignal)
  );
});

it.each(['unassigned', 'default_team'])(
  'shows the actual configured fallback %s rather than claiming waiting is the outcome',
  async fallback => {
    api.connectionDistribution.mockResolvedValue({
      policy: {
        enabled: true,
        mode: 'direct',
        team_ids: [11],
        max_open: 5,
        waiting_enabled: true,
        fallback,
        fallback_team_id: fallback === 'default_team' ? 22 : null,
      },
      teams,
    });
    wrapper = mount(ConnectionDistributionPolicy, {
      props: { accountId: 1, inboxId: 7, presentation: 'summary' },
    });
    await flushPromises();
    const card = wrapper.findAll('section').at(-1);
    expect(card.text()).toContain(
      fallback === 'unassigned'
        ? 'Leave unassigned'
        : 'Send to the default queue'
    );
    if (fallback === 'default_team') expect(card.text()).toContain('Support');
    expect(card.text()).not.toContain('Keep conversations waiting');
  }
);

it('keeps older distribution audit pages available after loading the first fifty changes', async () => {
  api.distributionHistory
    .mockResolvedValueOnce({
      data: [{ id: 51, previous_policy: {}, next_policy: {} }],
      next_cursor: 51,
    })
    .mockResolvedValueOnce({
      data: [{ id: 1, previous_policy: {}, next_policy: {} }],
      next_cursor: null,
    });
  wrapper = mountPolicy();
  await flushPromises();
  await wrapper
    .get('[data-testid="load-distribution-history"]')
    .trigger('click');
  await flushPromises();
  await wrapper
    .get('[data-testid="distribution-history-more"]')
    .trigger('click');
  await flushPromises();
  expect(api.distributionHistory).toHaveBeenLastCalledWith(
    7,
    expect.any(AbortSignal),
    51
  );
  expect(
    wrapper.get('[data-testid="distribution-history"]').findAll('li')
  ).toHaveLength(2);
});

it('saves calendar, availability, waiting and fallback choices with the connection policy', async () => {
  api.connectionDistribution.mockResolvedValue({
    policy: null,
    teams,
    calendar: {
      enabled: true,
      timezone: 'America/Sao_Paulo',
      weekly_schedule: [],
    },
  });
  wrapper = mountPolicy();
  await flushPromises();
  await wrapper.get('[data-testid="distribution-enabled"]').setValue(true);
  await wrapper.get('[data-team-id="11"]').setValue(true);
  await wrapper.get('[data-testid="distribution-schedule"]').setValue('inbox');
  await wrapper
    .get('[data-testid="distribution-availability"]')
    .setValue(false);
  await wrapper
    .get('[data-testid="distribution-capacity-enabled"]')
    .setValue(false);
  await wrapper
    .get('[data-testid="distribution-fallback"]')
    .setValue('default_team');
  await wrapper
    .get('[data-testid="distribution-fallback-team"]')
    .setValue('22');
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(api.saveConnectionDistribution).toHaveBeenCalledWith(
    7,
    expect.objectContaining({
      schedule: 'inbox',
      respect_availability: false,
      capacity_enabled: false,
      waiting_enabled: true,
      fallback: 'default_team',
      fallback_team_id: 22,
    }),
    expect.any(AbortSignal)
  );
  expect(wrapper.text()).toContain('America/Sao_Paulo');
});

it('requires a fallback team and does not offer a disabled calendar', async () => {
  wrapper = mountPolicy();
  await flushPromises();
  expect(
    wrapper
      .get('[data-testid="distribution-schedule"] option[value="inbox"]')
      .attributes('disabled')
  ).toBeDefined();
  await wrapper.get('[data-testid="distribution-enabled"]').setValue(true);
  await wrapper.get('[data-team-id="11"]').setValue(true);
  await wrapper
    .get('[data-testid="distribution-fallback"]')
    .setValue('default_team');
  await wrapper.get('form').trigger('submit');
  expect(api.saveConnectionDistribution).not.toHaveBeenCalled();
});

it('explains that an offline connection can save rules while waiting for reconnection', async () => {
  wrapper = mountPolicy();
  await wrapper.setProps({ connected: false });
  await flushPromises();
  expect(
    wrapper.get('[data-testid="distribution-awaiting-connection"]').text()
  ).toContain('reconnection');
});

it.each([
  [
    'en',
    'Included in the global selection',
    'Not included in the global selection',
    'Changed by System',
  ],
  [
    'pt_BR',
    'Incluída na seleção global',
    'Não incluída na seleção global',
    'Alteração pelo sistema',
  ],
])(
  'renders a real GLOBAL audit with disabled inclusion changes and System actor in %s',
  async (locale, included, excluded, actor) => {
    api.distributionHistory.mockResolvedValue({
      data: [
        {
          id: 1,
          user_id: null,
          previous_policy: {
            scope: 'GLOBAL',
            enabled: false,
            included: true,
            max_open: 3,
          },
          next_policy: {
            scope: 'GLOBAL',
            enabled: false,
            included: false,
            max_open: 3,
          },
        },
      ],
    });
    wrapper = mountPolicy();
    wrapper.vm.$i18n.locale = locale;
    try {
      await flushPromises();
      await wrapper
        .get('[data-testid="load-distribution-history"]')
        .trigger('click');
      await flushPromises();
      const history = wrapper.get('[data-testid="distribution-history"]');
      const snapshots = history.findAll('dd');
      expect(snapshots[0].text()).toContain(included);
      expect(snapshots[1].text()).toContain(excluded);
      expect(snapshots[0].text()).not.toBe(snapshots[1].text());
      expect(history.text()).toContain(actor);
      expect(history.text()).not.toMatch(
        /Mode unavailable|Tipo não disponível/
      );
      expect(api.saveConnectionDistribution).not.toHaveBeenCalled();
    } finally {
      wrapper.vm.$i18n.locale = 'en';
    }
  }
);

it.each(['en', 'pt_BR'])(
  'renders GLOBAL_ACCOUNT inbox IDs and capacity changes in %s',
  async locale => {
    api.distributionHistory.mockResolvedValue({
      data: [
        {
          id: 1,
          user_id: 4,
          previous_policy: {
            scope: 'GLOBAL_ACCOUNT',
            enabled: false,
            inbox_ids: [7, 8],
            max_open: 3,
          },
          next_policy: {
            scope: 'GLOBAL_ACCOUNT',
            enabled: true,
            inbox_ids: [8, 9],
            max_open: 6,
          },
        },
      ],
    });
    wrapper = mountPolicy();
    wrapper.vm.$i18n.locale = locale;
    try {
      await flushPromises();
      await wrapper
        .get('[data-testid="load-distribution-history"]')
        .trigger('click');
      await flushPromises();
      const history = wrapper.get('[data-testid="distribution-history"]');
      const snapshots = history.findAll('dd');
      expect(snapshots[0].text()).toContain('7, 8');
      expect(snapshots[0].text()).toContain('3');
      expect(snapshots[1].text()).toContain('8, 9');
      expect(snapshots[1].text()).toContain('6');
      expect(history.text()).not.toMatch(
        /Mode unavailable|Tipo não disponível/
      );
    } finally {
      wrapper.vm.$i18n.locale = 'en';
    }
  }
);

it('shows only saved policy in overview and preserves an unsaved edit while switching presentations', async () => {
  api.connectionDistribution.mockResolvedValue({
    policy: { enabled: true, mode: 'direct', team_ids: [11], max_open: 6 },
    teams,
  });
  wrapper = mountPolicy();
  await flushPromises();
  await wrapper.get('input[type="number"]').setValue(9);
  await wrapper.setProps({ presentation: 'summary' });
  expect(wrapper.find('form').exists()).toBe(false);
  expect(
    wrapper.get('[data-testid="distribution-saved-summary"]').text()
  ).toContain('Reception');
  expect(
    wrapper.get('[data-testid="distribution-saved-summary"]').text()
  ).toContain('6');
  expect(
    wrapper.find('[data-testid="load-distribution-history"]').exists()
  ).toBe(false);
  await wrapper.setProps({ presentation: 'history' });
  expect(wrapper.find('form').exists()).toBe(false);
  expect(
    wrapper.get('[data-testid="load-distribution-history"]').exists()
  ).toBe(true);
  expect(api.distributionHistory).not.toHaveBeenCalled();
  await wrapper.setProps({ presentation: 'policy' });
  expect(wrapper.get('input[type="number"]').element.value).toBe('9');
  expect(api.connectionDistribution).toHaveBeenCalledTimes(1);
  expect(api.saveConnectionDistribution).not.toHaveBeenCalled();
});

it('starts disabled without choosing queues or mutating the connection', async () => {
  wrapper = mountPolicy();
  await flushPromises();
  expect(
    wrapper.get('[data-testid="distribution-enabled"]').element.checked
  ).toBe(false);
  expect(
    wrapper.findAll('[data-team-id]').map(input => input.element.checked)
  ).toEqual([false, false]);
  expect(api.saveConnectionDistribution).not.toHaveBeenCalled();
  expect(api.distributionHistory).not.toHaveBeenCalled();
  expect(
    wrapper.get('[data-testid="distribution-global-fallback"]').text()
  ).toContain('account-wide');
});

it('saves explicit authorized queues and capacity for this existing connection', async () => {
  wrapper = mountPolicy();
  await flushPromises();
  await wrapper.get('[data-testid="distribution-enabled"]').setValue(true);
  await wrapper.get('[data-team-id="11"]').setValue(true);
  await wrapper.get('[data-team-id="22"]').setValue(true);
  await wrapper.get('input[type="number"]').setValue(6);
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(api.saveConnectionDistribution).toHaveBeenCalledWith(
    7,
    {
      enabled: true,
      mode: 'round_robin',
      team_ids: [11, 22],
      max_open: 6,
      visibility: 'shared',
      supervisor_ids: [],
      agent_limits: {},
      respect_availability: true,
      capacity_enabled: true,
      waiting_enabled: true,
      schedule: 'always',
      fallback: 'waiting',
      fallback_team_id: null,
    },
    expect.any(AbortSignal)
  );
  expect(wrapper.get('[role="status"]').text()).toContain('saved');
});

it('keeps the selected priority order when accessible move controls are used', async () => {
  wrapper = mountPolicy();
  await flushPromises();
  await wrapper.get('[data-testid="distribution-enabled"]').setValue(true);
  await wrapper.get('[data-team-id="11"]').setValue(true);
  await wrapper.get('[data-team-id="22"]').setValue(true);
  await wrapper.get('input[type="radio"][value="priority"]').setValue(true);
  await wrapper.get('button[aria-label="Move Support up"]').trigger('click');
  expect(
    wrapper.findAll('[data-selected-team]').map(row => row.text())
  ).toEqual([
    expect.stringContaining('Support'),
    expect.stringContaining('Reception'),
  ]);
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(api.saveConnectionDistribution).toHaveBeenCalledWith(
    7,
    {
      enabled: true,
      mode: 'priority',
      team_ids: [22, 11],
      max_open: 10,
      visibility: 'shared',
      supervisor_ids: [],
      agent_limits: {},
      respect_availability: true,
      capacity_enabled: true,
      waiting_enabled: true,
      schedule: 'always',
      fallback: 'waiting',
      fallback_team_id: null,
    },
    expect.any(AbortSignal)
  );
});

it('requires exactly one queue for direct distribution and does not silently drop a selection', async () => {
  wrapper = mountPolicy();
  await flushPromises();
  await wrapper.get('[data-testid="distribution-enabled"]').setValue(true);
  await wrapper.get('[data-team-id="11"]').setValue(true);
  await wrapper.get('[data-team-id="22"]').setValue(true);
  await wrapper.get('input[type="radio"][value="direct"]').setValue(true);
  await wrapper.get('form').trigger('submit');
  expect(api.saveConnectionDistribution).not.toHaveBeenCalled();
  expect(wrapper.get('[data-team-id="22"]').element.checked).toBe(true);
  await wrapper.get('[data-team-id="22"]').setValue(false);
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(api.saveConnectionDistribution).toHaveBeenCalledWith(
    7,
    {
      enabled: true,
      mode: 'direct',
      team_ids: [11],
      max_open: 10,
      visibility: 'shared',
      supervisor_ids: [],
      agent_limits: {},
      respect_availability: true,
      capacity_enabled: true,
      waiting_enabled: true,
      schedule: 'always',
      fallback: 'waiting',
      fallback_team_id: null,
    },
    expect.any(AbortSignal)
  );
});

it.each([0, 101, 1.5])(
  'blocks invalid capacity %s without calling the save API',
  async maxOpen => {
    wrapper = mountPolicy();
    await flushPromises();
    await wrapper.get('[data-testid="distribution-enabled"]').setValue(true);
    await wrapper.get('[data-team-id="11"]').setValue(true);
    await wrapper.get('input[type="number"]').setValue(maxOpen);
    await wrapper.get('form').trigger('submit');
    expect(api.saveConnectionDistribution).not.toHaveBeenCalled();
  }
);

it('requires an explicit queue to enable distribution but can save an explicitly disabled empty rule', async () => {
  wrapper = mountPolicy();
  await flushPromises();
  await wrapper.get('[data-testid="distribution-enabled"]').setValue(true);
  await wrapper.get('form').trigger('submit');
  expect(api.saveConnectionDistribution).not.toHaveBeenCalled();
  await wrapper.get('[data-testid="distribution-enabled"]').setValue(false);
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(api.saveConnectionDistribution).toHaveBeenCalledWith(
    7,
    {
      enabled: false,
      mode: 'round_robin',
      team_ids: [],
      max_open: 10,
      visibility: 'shared',
      supervisor_ids: [],
      agent_limits: {},
      respect_availability: true,
      capacity_enabled: true,
      waiting_enabled: true,
      schedule: 'always',
      fallback: 'waiting',
      fallback_team_id: null,
    },
    expect.any(AbortSignal)
  );
  expect(
    wrapper.find('[data-testid="distribution-global-fallback"]').exists()
  ).toBe(false);
});

it('does not silently save away a configured queue that is no longer authorized', async () => {
  api.connectionDistribution.mockResolvedValue({
    policy: {
      enabled: true,
      mode: 'priority',
      team_ids: [99, 11],
      max_open: 5,
    },
    teams,
  });
  wrapper = mountPolicy();
  await flushPromises();
  expect(wrapper.get('[data-selected-team="99"]').text()).toContain(
    'unavailable'
  );
  await wrapper.get('form').trigger('submit');
  expect(api.saveConnectionDistribution).not.toHaveBeenCalled();
});

it.each([null, {}])(
  'loads distribution history on demand and treats %j as no previous rule',
  async previousPolicy => {
    api.distributionHistory.mockResolvedValue({
      data: [
        {
          id: 1,
          user_id: 4,
          created_at: '2026-11-02T12:00:00Z',
          previous_policy: previousPolicy,
          next_policy: {
            enabled: true,
            mode: 'direct',
            team_ids: [22],
            max_open: 10,
          },
        },
      ],
    });
    wrapper = mountPolicy();
    await flushPromises();
    expect(api.distributionHistory).not.toHaveBeenCalled();
    await wrapper
      .get('[data-testid="load-distribution-history"]')
      .trigger('click');
    await flushPromises();
    expect(api.distributionHistory).toHaveBeenCalledWith(
      7,
      expect.any(AbortSignal)
    );
    const history = wrapper.get('[data-testid="distribution-history"]');
    expect(history.text()).toContain('Support');
    expect(history.text()).toContain('No connection-specific rule');
    expect(history.text()).toContain('4');
    expect(history.get('time').attributes('datetime')).toBe(
      '2026-11-02T12:00:00Z'
    );
    expect(history.text()).not.toContain('QR');
  }
);

it('does not show an empty-history success when its request fails', async () => {
  api.distributionHistory.mockRejectedValue(
    new Error('private stack and credential')
  );
  wrapper = mountPolicy();
  await flushPromises();
  await wrapper
    .get('[data-testid="load-distribution-history"]')
    .trigger('click');
  await flushPromises();
  expect(wrapper.get('[role="alert"]').exists()).toBe(true);
  expect(
    wrapper.find('[data-testid="empty-distribution-history"]').exists()
  ).toBe(false);
  expect(wrapper.text()).not.toContain('private stack');
});

it('aborts a delayed load and ignores its response when changing account and connection', async () => {
  let finishOld;
  api.connectionDistribution.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finishOld = resolve;
      })
  );
  wrapper = mountPolicy();
  const oldSignal = api.connectionDistribution.mock.calls[0][1];
  await wrapper.setProps({ accountId: 2, inboxId: 8 });
  await flushPromises();
  finishOld({
    policy: { enabled: true, mode: 'priority', team_ids: [99], max_open: 99 },
    teams: [{ id: 99, name: 'Previous tenant' }],
  });
  await flushPromises();
  expect(oldSignal.aborted).toBe(true);
  expect(wrapper.text()).not.toContain('Previous tenant');
  expect(wrapper.get('input[type="number"]').element.value).toBe('10');
  expect(
    wrapper.get('[data-testid="distribution-enabled"]').element.checked
  ).toBe(false);
});

it('keeps a late save response out of the next connection', async () => {
  let finishSave;
  api.saveConnectionDistribution.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finishSave = resolve;
      })
  );
  wrapper = mountPolicy();
  await flushPromises();
  await wrapper.get('[data-testid="distribution-enabled"]').setValue(true);
  await wrapper.get('[data-team-id="11"]').setValue(true);
  await wrapper.get('form').trigger('submit');
  await wrapper.setProps({ inboxId: 8 });
  await flushPromises();
  finishSave({
    policy: { enabled: true, mode: 'priority', team_ids: [11], max_open: 99 },
  });
  await flushPromises();
  expect(wrapper.get('input[type="number"]').element.value).toBe('10');
  expect(
    wrapper.get('[data-testid="distribution-enabled"]').element.checked
  ).toBe(false);
});

it('disables editing and clears queue details when authorization is denied', async () => {
  api.connectionDistribution.mockRejectedValue({ response: { status: 403 } });
  wrapper = mountPolicy();
  await flushPromises();
  expect(wrapper.get('fieldset').element.disabled).toBe(true);
  expect(wrapper.get('[role="alert"]').exists()).toBe(true);
  expect(wrapper.find('[data-team-id]').exists()).toBe(false);
  expect(api.saveConnectionDistribution).not.toHaveBeenCalled();
});

it('reports a failed save without exposing diagnostics or declaring it saved', async () => {
  api.saveConnectionDistribution.mockRejectedValue(
    new Error('private stack and credential')
  );
  wrapper = mountPolicy();
  await flushPromises();
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(wrapper.get('[role="alert"]').exists()).toBe(true);
  expect(wrapper.text()).not.toContain('private stack');
  expect(wrapper.text()).not.toContain('Distribution saved');
});

it('removes editable queue details when permission is revoked before saving', async () => {
  api.saveConnectionDistribution.mockRejectedValue({
    response: { status: 403 },
  });
  wrapper = mountPolicy();
  await flushPromises();
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(wrapper.get('fieldset').element.disabled).toBe(true);
  expect(wrapper.find('[data-team-id]').exists()).toBe(false);
  expect(wrapper.get('[role="alert"]').exists()).toBe(true);
});

it('aborts in-flight work on unmount', async () => {
  api.connectionDistribution.mockImplementation(() => new Promise(() => {}));
  wrapper = mountPolicy();
  const signal = api.connectionDistribution.mock.calls[0][1];
  wrapper.unmount();
  wrapper = null;
  expect(signal.aborted).toBe(true);
});
