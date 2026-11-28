import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive, ref } from 'vue';
import {
  enableAutoUnmount,
  flushPromises,
  shallowMount,
} from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import AgentCockpit from './AgentCockpit.vue';
import CallWorkspace from './CallWorkspace.vue';
import VisualShowcasePage from '../components/visual/VisualShowcasePage.vue';

const mocks = vi.hoisted(() => ({ route: null, user: null, replace: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => mocks.user,
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: mocks.replace }),
}));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { context: vi.fn(), calls: vi.fn(), callbacks: vi.fn() },
}));
const data = (active = 0, callbacks = 0, cases = 0) => ({
  counts: {
    active_calls: active,
    pending_callbacks: callbacks,
    open_cases: cases,
  },
  capabilities: { operate: true },
});
const render = () =>
  shallowMount(AgentCockpit, { global: { stubs: { RouterLink: true } } });
const screen = wrapper =>
  wrapper.findComponent(VisualShowcasePage).props('screen');
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ params: { accountId: '1' }, query: {} });
  mocks.user = ref({
    id: 4,
    type: 'User',
    accounts: [1, 2].map(id => ({
      id,
      role: 'agent',
      custom_role_id: 7,
      permissions: ['jrc_contact_center_view'],
    })),
  });
  API.context.mockResolvedValue({ data: data() });
  API.calls.mockResolvedValue({ data: { items: [] } });
  API.callbacks.mockResolvedValue({ data: { items: [] } });
});

describe('native cockpit source and authority', () => {
  it('keeps pending and rejected observations unknown without illustrative counts, client rows or actions', async () => {
    let reject;
    API.context.mockImplementationOnce(
      () =>
        new Promise((resolve, fail) => {
          reject = fail;
        })
    );
    const wrapper = render();
    expect(screen(wrapper).metrics.map(item => item.value)).toEqual([
      '—',
      '—',
      '—',
      '—',
    ]);
    expect(screen(wrapper).primary).toBeNull();
    expect(screen(wrapper).secondary).toBeNull();
    expect(
      wrapper.findComponent(VisualShowcasePage).props('showDemoBadge')
    ).toBe(false);
    expect(
      wrapper.findComponent(VisualShowcasePage).props('overviewOnly')
    ).toBe(true);
    reject(new Error('SYNTHETIC denied read'));
    await flushPromises();
    expect(screen(wrapper).metrics.map(item => item.value)).toEqual([
      '—',
      '—',
      '—',
      '—',
    ]);
    expect(screen(wrapper).status.tone).toBe('ruby');
  });

  it('labels actual active calls, pending callbacks and open cases without calling them satisfaction or today attendance', async () => {
    API.context.mockResolvedValueOnce({ data: data(7, 3, 2) });
    const wrapper = render();
    await flushPromises();
    expect(screen(wrapper).metrics.map(item => item.value)).toEqual([
      7,
      3,
      '—',
      2,
    ]);
    expect(screen(wrapper).metrics[0].label).toBe('Chamadas ativas');
    expect(screen(wrapper).metrics[1].label).toBe('Retornos pendentes');
    expect(screen(wrapper).metrics[3].label).toBe('Ocorrências abertas');
    expect(screen(wrapper).metrics[3].icon).toBe('i-lucide-ticket');
    expect(screen(wrapper).metrics.every(item => item.trend === '')).toBe(true);
    expect(screen(wrapper).metrics[2].detail).toContain('pendente de fonte');
  });

  it('preserves real zero while keeping unavailable average time unknown', async () => {
    const wrapper = render();
    await flushPromises();
    expect(screen(wrapper).metrics.map(item => item.value)).toEqual([
      0,
      0,
      '—',
      0,
    ]);
    expect(screen(wrapper).status.tone).toBe('blue');
  });

  it('ignores the previous account response after switching without reviving its observations', async () => {
    let resolve;
    API.context.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = render();
    mocks.route.params.accountId = '2';
    await flushPromises();
    resolve({ data: data(99, 98, 97) });
    await flushPromises();
    expect(screen(wrapper).metrics.map(item => item.value)).toEqual([
      0,
      0,
      '—',
      0,
    ]);
    expect(API.context).toHaveBeenLastCalledWith('2');
  });

  it('clears selected native call and metrics when the same account profile changes and a fresh read is denied', async () => {
    mocks.route.query.callId = '4';
    API.context.mockResolvedValueOnce({ data: data(9, 8, 7) });
    const wrapper = render();
    await flushPromises();
    expect(wrapper.findComponent(CallWorkspace).exists()).toBe(true);
    API.context.mockRejectedValueOnce({ response: { status: 401 } });
    mocks.user.value.accounts[0].custom_role_id = 8;
    await flushPromises();
    expect(screen(wrapper).metrics.map(item => item.value)).toEqual([
      '—',
      '—',
      '—',
      '—',
    ]);
    expect(wrapper.findComponent(CallWorkspace).exists()).toBe(false);
    expect(screen(wrapper).status.tone).toBe('ruby');
  });

  it('does not request account data after authentication disappears', async () => {
    const wrapper = render();
    await flushPromises();
    const requests = API.context.mock.calls.length;
    mocks.user.value = {};
    await flushPromises();
    expect(API.context.mock.calls.length).toBe(requests);
    expect(screen(wrapper).metrics.map(item => item.value)).toEqual([
      '—',
      '—',
      '—',
      '—',
    ]);
  });

  it('clears private observations after a denied refresh from the native call workspace event', async () => {
    mocks.route.query.callId = '4';
    API.context.mockResolvedValueOnce({ data: data(9, 8, 7) });
    const wrapper = render();
    await flushPromises();
    API.callbacks.mockRejectedValueOnce({ response: { status: 401 } });
    wrapper.findComponent(CallWorkspace).vm.$emit('created');
    await flushPromises();
    expect(screen(wrapper).metrics.map(item => item.value)).toEqual([
      '—',
      '—',
      '—',
      '—',
    ]);
    expect(wrapper.findComponent(CallWorkspace).exists()).toBe(false);
    expect(screen(wrapper).status.tone).toBe('ruby');
  });

  it('clears a selected call when native eligibility changes even if role and permissions stay the same', async () => {
    mocks.route.query.callId = '4';
    API.context.mockResolvedValueOnce({ data: data(9, 8, 7) });
    const wrapper = render();
    await flushPromises();
    expect(wrapper.findComponent(CallWorkspace).exists()).toBe(true);
    API.context.mockRejectedValueOnce({ response: { status: 401 } });
    mocks.user.value.accounts[0].contact_center_eligible = false;
    await flushPromises();
    expect(API.context).toHaveBeenCalledTimes(2);
    expect(wrapper.findComponent(CallWorkspace).exists()).toBe(false);
    expect(screen(wrapper).metrics.map(item => item.value)).toEqual([
      '—',
      '—',
      '—',
      '—',
    ]);
  });
  it('preserves the existing call workspace and counts for a presence-only membership refresh', async () => {
    mocks.route.query.callId = '4';
    API.context.mockResolvedValueOnce({ data: data(9, 8, 7) });
    const wrapper = render();
    await flushPromises();
    mocks.user.value.accounts[0].availability = 'busy';
    await flushPromises();
    expect(API.context).toHaveBeenCalledTimes(1);
    expect(wrapper.findComponent(CallWorkspace).exists()).toBe(true);
    expect(screen(wrapper).metrics.map(item => item.value)).toEqual([
      9,
      8,
      '—',
      7,
    ]);
  });
});
