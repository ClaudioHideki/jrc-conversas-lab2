import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import AgentStateHistory from './AgentStateHistory.vue';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { agentStateHistory: vi.fn() },
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values = {}) => [key, ...Object.values(values)].join(' '),
  }),
}));
enableAutoUnmount(afterEach);
const Dialog = {
  props: ['title'],
  emits: ['close'],
  setup(_props, { expose, emit }) {
    const visible = ref(false);
    expose({
      open: () => {
        visible.value = true;
      },
      close: () => {
        visible.value = false;
        emit('close');
      },
    });
    return { visible };
  },
  template:
    '<section v-if="visible" role="dialog"><h2>{{ title }}</h2><slot /></section>',
};
const context = (control = true) => ({
  capabilities: { control },
  queues: [{ id: '6', name: 'SYNTHETIC allowed queue' }],
});
const render = (props = {}) =>
  mount(AgentStateHistory, {
    props: { accountId: '1', context: context(), ...props },
    global: { stubs: { Dialog } },
  });
const data = () => ({
  data: {
    account_id: '1',
    items: [
      {
        id: '9',
        account_user_id: '5',
        agent_name: 'SYNTHETIC authorized actor',
        queue_name: 'SYNTHETIC allowed queue',
        state: 'paused',
        started_at: '2026-11-18T02:00:00Z',
        ended_at: '2026-11-18T02:01:00Z',
        duration_seconds: 60,
        source: 'local',
        provider_confirmed: false,
      },
    ],
    meta: { page: 1, per_page: 20, total: 1, pages: 1 },
    window: {
      from: '2026-11-17',
      to: '2026-11-17',
      timezone: 'America/Sao_Paulo',
    },
  },
});
beforeEach(() => {
  vi.clearAllMocks();
  API.agentStateHistory.mockResolvedValue(data());
});

describe('operational pause and state history popup', () => {
  it('does not expose an opener or request rows without native control permission', async () => {
    const wrapper = render({ context: context(false) });
    await flushPromises();
    expect(wrapper.find('[data-open-state-history]').exists()).toBe(false);
    expect(API.agentStateHistory).not.toHaveBeenCalled();
  });

  it('opens a paginated readonly projection with native translated states and account timezone', async () => {
    const wrapper = render();
    await wrapper.find('[data-open-state-history]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-history-row]').text()).toContain(
      'SYNTHETIC authorized actor'
    );
    expect(wrapper.text()).toContain('JRC_CONTACT_CENTER.AGENT.STATES.paused');
    expect(wrapper.text()).toContain('17/11/2026');
    expect(wrapper.text()).toContain('00:01:00');
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.STATE_HISTORY.UNCONFIRMED'
    );
    expect(wrapper.find('[data-history-next]').element.disabled).toBe(true);
    expect(
      wrapper.find('[data-history-filters]').attributes('open')
    ).toBeUndefined();
    expect(wrapper.find('[data-history-filters] summary').text()).toContain(
      'JRC_CONTACT_CENTER.STATE_HISTORY.FILTERS'
    );
    expect(API.agentStateHistory).toHaveBeenCalledTimes(1);
  });

  it('closes and clears all protected rows immediately on a profile or corporate context change', async () => {
    const wrapper = render();
    await wrapper.find('[data-open-state-history]').trigger('click');
    await flushPromises();
    await wrapper.setProps({ context: { ...context(), queues: [] } });
    expect(wrapper.find('[data-history-row]').exists()).toBe(false);
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    await wrapper.setProps({ context: context(false) });
    expect(wrapper.find('[data-open-state-history]').exists()).toBe(false);
    expect(API.agentStateHistory).toHaveBeenCalledTimes(1);
  });

  it('shows a failure and requires an explicit retry instead of treating a denial as an empty successful list', async () => {
    API.agentStateHistory.mockRejectedValueOnce({ response: { status: 403 } });
    const wrapper = render();
    await wrapper.find('[data-open-state-history]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(wrapper.find('[data-history-empty]').exists()).toBe(false);
    expect(API.agentStateHistory).toHaveBeenCalledTimes(1);
    await wrapper.find('[data-history-retry]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(wrapper.find('[data-history-row]').exists()).toBe(true);
  });
});
