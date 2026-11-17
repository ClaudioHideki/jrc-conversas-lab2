import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive } from 'vue';
import { flushPromises, shallowMount } from '@vue/test-utils';
import JrcContactCenterAPI from 'dashboard/api/jrcContactCenter';
import VisualShowcasePage from '../components/visual/VisualShowcasePage.vue';
import SupervisorPage from './SupervisorPage.vue';

const mocks = vi.hoisted(() => ({ route: null }));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { units: vi.fn(), queues: vi.fn(), supervisor: vi.fn() },
}));

describe('native supervisor observed data', () => {
  let wrapper;
  beforeEach(() => {
    vi.useFakeTimers();
    mocks.route = reactive({ params: { accountId: '1' } });
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
});
