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
  await wrapper.get('select').setValue('priority');
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
  await wrapper.get('select').setValue('direct');
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
