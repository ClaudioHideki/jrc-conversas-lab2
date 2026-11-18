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
});
