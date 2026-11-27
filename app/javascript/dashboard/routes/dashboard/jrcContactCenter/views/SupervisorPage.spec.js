import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive, ref } from 'vue';
import { flushPromises, shallowMount } from '@vue/test-utils';
import JrcContactCenterAPI from 'dashboard/api/jrcContactCenter';
import VisualShowcasePage from '../components/visual/VisualShowcasePage.vue';
import SupervisorPage from './SupervisorPage.vue';

const mocks = vi.hoisted(() => ({ route: null, user: null }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => mocks.user,
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { units: vi.fn(), queues: vi.fn(), supervisor: vi.fn() },
}));

describe('native supervisor observed data', () => {
  let wrapper;
  beforeEach(() => {
    vi.useFakeTimers();
    mocks.route = reactive({ params: { accountId: '1' } });
    mocks.user = ref({
      id: 4,
      type: 'User',
      accounts: [
        {
          id: 1,
          role: 'agent',
          custom_role_id: 7,
          permissions: [
            'jrc_contact_center_view',
            'jrc_contact_center_supervise',
          ],
        },
      ],
    });
    JrcContactCenterAPI.units.mockResolvedValue({ data: { items: [] } });
    JrcContactCenterAPI.queues.mockResolvedValue({ data: { items: [] } });
    JrcContactCenterAPI.supervisor.mockResolvedValue({
      data: { agents: [], queues: [] },
    });
  });
  afterEach(() => {
    wrapper?.unmount();
    vi.useRealTimers();
  });

  it('does not turn an outstanding or rejected read into zero, live status or illustrative metrics', async () => {
    let reject;
    JrcContactCenterAPI.supervisor.mockImplementationOnce(
      () =>
        new Promise((resolve, fail) => {
          reject = fail;
        })
    );
    wrapper = shallowMount(SupervisorPage);
    const view = wrapper.findComponent(VisualShowcasePage);
    expect(view.props('screen').metrics.map(metric => metric.value)).toEqual([
      '—',
      '—',
      '—',
      '—',
    ]);
    expect(view.props('screen').primary).toBeNull();
    expect(view.props('showDemoBadge')).toBe(false);
    expect(view.props('overviewOnly')).toBe(true);
    reject(new Error('synthetic unavailable read'));
    await flushPromises();
    expect(view.props('screen').metrics.map(metric => metric.value)).toEqual([
      '—',
      '—',
      '—',
      '—',
    ]);
    expect(view.props('screen').status.tone).toBe('ruby');
  });

  it('preserves real zero counts without manufacturing SLA or abandonment rates', async () => {
    wrapper = shallowMount(SupervisorPage);
    await flushPromises();
    const screen = wrapper.findComponent(VisualShowcasePage).props('screen');
    expect(screen.metrics.map(metric => metric.value)).toEqual([
      0,
      0,
      '—',
      '—',
    ]);
    expect(screen.metrics.every(metric => metric.trend === '')).toBe(true);
    expect(screen.secondary).toBeNull();
    expect(screen.status.tone).toBe('blue');
  });

  it('uses the authorized local agent and queue counts instead of visual reference values', async () => {
    JrcContactCenterAPI.supervisor.mockResolvedValueOnce({
      data: {
        agents: [{ state: 'available' }, { state: 'in_call' }],
        queues: [
          { id: '1', name: 'SYNTHETIC queue', status: 'active', waiting: 7 },
        ],
      },
    });
    wrapper = shallowMount(SupervisorPage);
    await flushPromises();
    const screen = wrapper.findComponent(VisualShowcasePage).props('screen');
    expect(screen.metrics.map(metric => metric.value)).toEqual([
      2,
      7,
      '—',
      '—',
    ]);
    expect(screen.metrics[0].detail).toContain('1');
    expect(screen.primary).toBeNull();
    expect(wrapper.text()).not.toContain('Carla Mendes');
    expect(wrapper.text()).not.toContain('91,2%');
  });

  it('discards stale observed data after polling fails and clears the error after a fresh success', async () => {
    wrapper = shallowMount(SupervisorPage);
    await flushPromises();
    const view = wrapper.findComponent(VisualShowcasePage);
    JrcContactCenterAPI.supervisor.mockRejectedValueOnce(
      new Error('synthetic denied')
    );
    await vi.advanceTimersByTimeAsync(5000);
    await flushPromises();
    expect(view.props('screen').metrics.map(metric => metric.value)).toEqual([
      '—',
      '—',
      '—',
      '—',
    ]);
    expect(view.props('screen').status.tone).toBe('ruby');
    await vi.advanceTimersByTimeAsync(5000);
    await flushPromises();
    expect(view.props('screen').metrics.map(metric => metric.value)).toEqual([
      0,
      0,
      '—',
      '—',
    ]);
    expect(view.props('screen').status.tone).toBe('blue');
  });

  it('does not restore a different account snapshot that finishes after navigation', async () => {
    let old;
    JrcContactCenterAPI.supervisor.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          old = resolve;
        })
    );
    wrapper = shallowMount(SupervisorPage);
    mocks.route.params.accountId = '2';
    await flushPromises();
    old({ data: { agents: [{ name: 'SYNTHETIC old account' }], queues: [] } });
    await flushPromises();
    expect(JrcContactCenterAPI.supervisor).toHaveBeenCalledWith('2');
    expect(
      wrapper
        .findComponent(VisualShowcasePage)
        .props('screen')
        .metrics.map(metric => metric.value)
    ).toEqual([0, 0, '—', '—']);
    expect(wrapper.text()).not.toContain('SYNTHETIC old account');
  });

  it('keeps only one periodic observation in flight while a slow real read is outstanding', async () => {
    wrapper = shallowMount(SupervisorPage);
    await flushPromises();
    let finish;
    JrcContactCenterAPI.supervisor.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    await vi.advanceTimersByTimeAsync(5000);
    await flushPromises();
    const count = JrcContactCenterAPI.supervisor.mock.calls.length;
    await vi.advanceTimersByTimeAsync(15000);
    expect(JrcContactCenterAPI.supervisor.mock.calls.length).toBe(count);
    expect(
      wrapper.findComponent(VisualShowcasePage).props('screen').status.tone
    ).toBe('slate');
    finish({ data: { agents: [], queues: [] } });
    await flushPromises();
    await vi.advanceTimersByTimeAsync(5000);
    expect(JrcContactCenterAPI.supervisor.mock.calls.length).toBe(count + 1);
  });

  it('discards a prior profile observation even when it finishes after a fresh profile reload', async () => {
    wrapper = shallowMount(SupervisorPage);
    await flushPromises();
    let finish;
    JrcContactCenterAPI.supervisor.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    await vi.advanceTimersByTimeAsync(5000);
    await flushPromises();
    mocks.user.value.accounts[0].permissions = [];
    await flushPromises();
    finish({
      data: {
        agents: [{ name: 'SYNTHETIC stale actor', state: 'available' }],
        queues: [],
      },
    });
    await flushPromises();
    expect(
      wrapper.findComponent(VisualShowcasePage).props('screen').metrics[0].value
    ).toBe(0);
  });

  it('clears authorized unit names after a rejected poll and does not retain a misleading inventory', async () => {
    JrcContactCenterAPI.units.mockResolvedValueOnce({
      data: {
        items: [
          {
            id: 1,
            name: 'SYNTHETIC PRIVATE UNIT',
            code: 'PRIVATE',
            kind: 'finance',
            status: 'active',
          },
        ],
      },
    });
    wrapper = shallowMount(SupervisorPage, {
      global: {
        stubs: {
          VisualSectionCard: { template: '<section><slot /></section>' },
        },
      },
    });
    await flushPromises();
    expect(wrapper.text()).toContain('SYNTHETIC PRIVATE UNIT');
    expect(wrapper.text()).toContain('Financeiro');
    expect(wrapper.find('visual-status-badge-stub').attributes('label')).toBe(
      'Ativo'
    );
    JrcContactCenterAPI.supervisor.mockRejectedValueOnce(
      new Error('synthetic authority denied')
    );
    await vi.advanceTimersByTimeAsync(5000);
    await flushPromises();
    expect(wrapper.text()).not.toContain('SYNTHETIC PRIVATE UNIT');
    expect(
      wrapper.findComponent(VisualShowcasePage).props('screen').status.tone
    ).toBe('ruby');
  });

  it('clears observations when authentication changes instead of retaining the old actor snapshot', async () => {
    JrcContactCenterAPI.supervisor.mockResolvedValueOnce({
      data: {
        agents: [{ name: 'SYNTHETIC prior actor', state: 'available' }],
        queues: [],
      },
    });
    wrapper = shallowMount(SupervisorPage);
    await flushPromises();
    expect(
      wrapper.findComponent(VisualShowcasePage).props('screen').metrics[0].value
    ).toBe(1);
    const count = JrcContactCenterAPI.supervisor.mock.calls.length;
    mocks.user.value = {};
    await flushPromises();
    await vi.advanceTimersByTimeAsync(5000);
    expect(
      wrapper.findComponent(VisualShowcasePage).props('screen').metrics[0].value
    ).toBe('—');
    expect(JrcContactCenterAPI.supervisor.mock.calls.length).toBe(count);
  });

  it('shows the authorized observed pause duration and exceeded notice without exposing operator metadata', async () => {
    JrcContactCenterAPI.supervisor.mockResolvedValueOnce({
      data: {
        agents: [
          {
            account_user_id: '42',
            name: 'SYNTHETIC operator',
            state: 'paused',
            eligible: false,
            pause_notice: { elapsed_seconds: 61, exceeded: true },
          },
        ],
        queues: [],
      },
    });
    wrapper = shallowMount(SupervisorPage, {
      global: {
        stubs: {
          VisualSectionCard: { template: '<section><slot /></section>' },
        },
      },
    });
    await flushPromises();
    expect(wrapper.get('[data-supervisor-pause-notice]').text()).toContain(
      'Tempo em pausa: 01:01'
    );
    expect(
      wrapper.get('[data-supervisor-pause-notice] [role="status"]').text()
    ).toContain('A pausa continua ativa');
    expect(wrapper.find('[data-own-pause-justification]').exists()).toBe(false);
  });

  it('keeps real zero without an exceeded alert and hides absent or unscoped duration evidence', async () => {
    JrcContactCenterAPI.supervisor.mockResolvedValueOnce({
      data: {
        agents: [
          {
            account_user_id: '42',
            name: 'SYNTHETIC operator',
            state: 'paused',
            eligible: false,
            pause_notice: { elapsed_seconds: 0, exceeded: false },
          },
          {
            account_user_id: '43',
            name: 'SYNTHETIC without evidence',
            state: 'paused',
            pause_notice: null,
          },
        ],
        queues: [],
      },
    });
    wrapper = shallowMount(SupervisorPage, {
      global: {
        stubs: {
          VisualSectionCard: { template: '<section><slot /></section>' },
        },
      },
    });
    await flushPromises();
    expect(wrapper.findAll('[data-supervisor-pause-notice]')).toHaveLength(1);
    expect(wrapper.get('[data-supervisor-pause-notice]').text()).toContain(
      'Tempo em pausa: 00:00'
    );
    expect(
      wrapper.find('[data-supervisor-pause-notice] [role="status"]').exists()
    ).toBe(false);
  });

  it('shows only the scoped pending or blocked deferred-pause signal without private request details', async () => {
    JrcContactCenterAPI.supervisor.mockResolvedValueOnce({
      data: {
        agents: [
          {
            account_user_id: '42',
            name: 'SYNTHETIC waiting',
            state: 'acw',
            deferred_pause_notice: { state: 'pending' },
          },
          {
            account_user_id: '43',
            name: 'SYNTHETIC review',
            state: 'available',
            deferred_pause_notice: { state: 'blocked' },
          },
          {
            account_user_id: '44',
            name: 'SYNTHETIC unscoped',
            state: 'acw',
            deferred_pause_notice: null,
          },
        ],
        queues: [],
      },
    });
    wrapper = shallowMount(SupervisorPage, {
      global: {
        stubs: {
          VisualSectionCard: { template: '<section><slot /></section>' },
        },
      },
    });
    await flushPromises();
    const notices = wrapper.findAll('[data-supervisor-deferred-pause-notice]');
    expect(notices).toHaveLength(2);
    expect(notices[0].text()).toContain('aguardando');
    expect(notices[1].text()).toContain('revisão');
    expect(wrapper.find('[data-own-pause-justification]').exists()).toBe(false);
  });
  it.each([
    ['available', 0, '00:00'],
    ['paused', 61, '01:01'],
    ['in_call', 3661, '01:01:01'],
    ['offline', 0, '00:00'],
  ])(
    'shows only native observed %s duration with real seconds %s',
    async (state, elapsed, expected) => {
      JrcContactCenterAPI.supervisor.mockResolvedValueOnce({
        data: {
          agents: [
            {
              account_user_id: '42',
              name: 'SYNTHETIC local state',
              state,
              state_version: '7',
              state_notice: {
                state,
                state_version: '7',
                elapsed_seconds: elapsed,
              },
            },
          ],
          queues: [],
        },
      });
      wrapper = shallowMount(SupervisorPage, {
        global: {
          stubs: {
            VisualSectionCard: { template: '<section><slot /></section>' },
          },
        },
      });
      await flushPromises();
      expect(
        wrapper.get('[data-supervisor-native-state-duration]').text()
      ).toBe('Tempo no estado: ' + expected);
      expect(wrapper.find('[data-supervisor-pause-notice]').exists()).toBe(
        false
      );
    }
  );

  it('never derives a visible duration from raw timestamps, mismatched versions, states or invalid counts', async () => {
    const notices = [
      null,
      { state: 'available', state_version: 'old', elapsed_seconds: 5 },
      { state: 'paused', state_version: '7', elapsed_seconds: 5 },
      { state: 'available', state_version: '7', elapsed_seconds: -1 },
      { state: 'available', state_version: '7', elapsed_seconds: null },
    ];
    JrcContactCenterAPI.supervisor.mockResolvedValueOnce({
      data: {
        agents: notices.map((notice, index) => ({
          account_user_id: String(index + 42),
          name: 'SYNTHETIC missing evidence',
          state: 'available',
          state_version: '7',
          started_at: '2026-11-01T00:00:00Z',
          state_notice: notice,
        })),
        queues: [],
      },
    });
    wrapper = shallowMount(SupervisorPage, {
      global: {
        stubs: {
          VisualSectionCard: { template: '<section><slot /></section>' },
        },
      },
    });
    await flushPromises();
    expect(
      wrapper.findAll('[data-supervisor-native-state-duration]')
    ).toHaveLength(0);
  });

  it('removes the previous observed duration when the next authorized poll has no state observation', async () => {
    const agent = {
      account_user_id: '42',
      name: 'SYNTHETIC scoped state',
      state: 'available',
      state_version: '7',
    };
    JrcContactCenterAPI.supervisor
      .mockResolvedValueOnce({
        data: {
          agents: [
            {
              ...agent,
              state_notice: {
                state: 'available',
                state_version: '7',
                elapsed_seconds: 61,
              },
            },
          ],
          queues: [],
        },
      })
      .mockResolvedValueOnce({
        data: { agents: [{ ...agent, state_notice: null }], queues: [] },
      });
    wrapper = shallowMount(SupervisorPage, {
      global: {
        stubs: {
          VisualSectionCard: { template: '<section><slot /></section>' },
        },
      },
    });
    await flushPromises();
    expect(
      wrapper.findAll('[data-supervisor-native-state-duration]')
    ).toHaveLength(1);
    await vi.advanceTimersByTimeAsync(5000);
    await flushPromises();
    expect(
      wrapper.findAll('[data-supervisor-native-state-duration]')
    ).toHaveLength(0);
  });
});
