import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive, ref } from 'vue';
import {
  enableAutoUnmount,
  flushPromises,
  shallowMount,
} from '@vue/test-utils';
import PauseOperationalWorkspace from './PauseOperationalWorkspace.vue';
import PauseCatalogEditor from './PauseCatalogEditor.vue';
import RoutingDraftWorkspace from './RoutingDraftWorkspace.vue';
import AgentStateHistory from './AgentStateHistory.vue';
import SupervisorPage from '../views/SupervisorPage.vue';

const mocks = vi.hoisted(() => ({
  route: null,
  user: null,
  replace: vi.fn(),
  historyOpen: vi.fn(),
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: mocks.replace }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => mocks.user,
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const context = () => ({
  capabilities: { configure: true, supervise: true, control: true },
  units: [{ id: '11', name: 'SYNTHETIC covered unit' }],
});
const render = (value = context()) =>
  shallowMount(PauseOperationalWorkspace, {
    props: { accountId: '1', context: value },
    global: {
      stubs: {
        AgentStateHistory: {
          name: 'AgentStateHistory',
          props: ['accountId', 'context'],
          setup(_props, { expose }) {
            expose({ open: mocks.historyOpen });
          },
          template: '<section />',
        },
      },
    },
  });
const tabs = wrapper =>
  wrapper
    .findAll('[data-pause-workspace-tab]')
    .map(node => node.attributes('data-pause-workspace-tab'));

enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ query: {} });
  mocks.user = ref({
    id: 4,
    type: 'User',
    accounts: [
      { id: 1, role: 'agent', corporate_coverage: { unit_ids: [11] } },
    ],
  });
  mocks.replace.mockImplementation(async ({ query }) => {
    mocks.route.query = Object.fromEntries(
      Object.entries(query).filter(([, value]) => value !== undefined)
    );
  });
});

describe('native pause operational workspace reuse', () => {
  it('opens only the existing pause catalog by default, without mounting polling or history readers', () => {
    const wrapper = render();
    expect(tabs(wrapper)).toEqual([
      'motives',
      'distribution',
      'availability',
      'history',
    ]);
    expect(wrapper.findComponent(PauseCatalogEditor).exists()).toBe(true);
    expect(wrapper.findComponent(RoutingDraftWorkspace).exists()).toBe(false);
    expect(wrapper.findComponent(SupervisorPage).exists()).toBe(false);
    expect(wrapper.findComponent(AgentStateHistory).exists()).toBe(false);
  });

  it('uses the current account and native distribution component and preserves unrelated catalog filters in the URL', async () => {
    mocks.route.query = { pauses_q: 'SYNTHETIC', pauses_page: '2' };
    const wrapper = render();
    await wrapper
      .get('[data-pause-workspace-tab="distribution"]')
      .trigger('click');
    await flushPromises();
    expect(mocks.replace).toHaveBeenCalledWith({
      query: {
        pauses_q: 'SYNTHETIC',
        pauses_page: '2',
        pauses_tab: 'distribution',
      },
    });
    expect(wrapper.findComponent(PauseCatalogEditor).exists()).toBe(false);
    const native = wrapper.getComponent(RoutingDraftWorkspace);
    expect(native.props('accountId')).toBe('1');
    expect(native.props('context')).toEqual(context());
  });

  it('restores the availability tab from the URL and mounts only the native supervisor', () => {
    mocks.route.query.pauses_tab = 'availability';
    const wrapper = render();
    expect(wrapper.findComponent(SupervisorPage).exists()).toBe(true);
    expect(wrapper.findComponent(PauseCatalogEditor).exists()).toBe(false);
    expect(wrapper.findComponent(AgentStateHistory).exists()).toBe(false);
    expect(
      wrapper
        .get('[data-pause-workspace-tab="availability"]')
        .attributes('aria-selected')
    ).toBe('true');
  });

  it('uses the existing authorized history dialog and returns to the catalog without losing its filters', async () => {
    mocks.route.query = { pauses_tab: 'history', pauses_q: 'SYNTHETIC' };
    const wrapper = render();
    await flushPromises();
    expect(mocks.historyOpen).toHaveBeenCalledTimes(1);
    expect(wrapper.getComponent(AgentStateHistory).props('accountId')).toBe(
      '1'
    );
    expect(wrapper.getComponent(AgentStateHistory).props('context')).toEqual(
      context()
    );
    await wrapper.get('[data-pause-workspace-tab="motives"]').trigger('click');
    await flushPromises();
    expect(mocks.route.query).toEqual({ pauses_q: 'SYNTHETIC' });
    expect(wrapper.findComponent(AgentStateHistory).exists()).toBe(false);
  });

  it('does not turn configure authority into supervision and refuses a manipulated availability query', () => {
    mocks.route.query.pauses_tab = 'availability';
    const value = context();
    value.capabilities.supervise = false;
    const wrapper = render(value);
    expect(tabs(wrapper)).not.toContain('availability');
    expect(wrapper.findComponent(SupervisorPage).exists()).toBe(false);
    expect(wrapper.findComponent(PauseCatalogEditor).exists()).toBe(true);
  });

  it('removes a denied active destination when current native capabilities change', async () => {
    mocks.route.query.pauses_tab = 'distribution';
    const wrapper = render();
    const value = context();
    value.capabilities.configure = false;
    await wrapper.setProps({ context: value });
    expect(tabs(wrapper)).toEqual(['availability', 'history']);
    expect(wrapper.findComponent(RoutingDraftWorkspace).exists()).toBe(false);
    expect(wrapper.findComponent(SupervisorPage).exists()).toBe(true);
  });

  it('shows denial without mounting any native destination when no capability remains', () => {
    const wrapper = render({ capabilities: {}, units: [] });
    expect(tabs(wrapper)).toEqual([]);
    expect(wrapper.find('[data-pause-workspace-panel]').exists()).toBe(false);
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'PAUSE_WORKSPACE.DENIED'
    );
  });

  it('replaces the active reader on a same-account corporate scope change while ordinary presence refreshes preserve it', async () => {
    mocks.route.query.pauses_tab = 'availability';
    const wrapper = render();
    const original = wrapper.getComponent(SupervisorPage).vm;
    mocks.user.value.accounts[0].availability = 'online';
    await flushPromises();
    expect(wrapper.getComponent(SupervisorPage).vm).toBe(original);
    mocks.user.value.accounts[0].corporate_coverage.unit_ids = [];
    await flushPromises();
    expect(wrapper.getComponent(SupervisorPage).vm).not.toBe(original);
  });

  it('moves through authorized tabs with the keyboard and wraps without selecting a hidden destination', async () => {
    const wrapper = render();
    await wrapper
      .get('[data-pause-workspace-tab="motives"]')
      .trigger('keydown', { key: 'ArrowLeft' });
    await flushPromises();
    expect(mocks.route.query.pauses_tab).toBe('history');
    await wrapper
      .get('[data-pause-workspace-tab="history"]')
      .trigger('keydown', { key: 'Home' });
    await flushPromises();
    expect(mocks.route.query.pauses_tab).toBeUndefined();
    expect(
      wrapper.get('[data-pause-workspace-tab="motives"]').attributes('tabindex')
    ).toBe('0');
  });

  it('forwards only the native catalog save notification and does not create a second write mechanism', async () => {
    const wrapper = render();
    wrapper.getComponent(PauseCatalogEditor).vm.$emit('changed');
    await flushPromises();
    expect(wrapper.emitted('changed')).toHaveLength(1);
    expect(mocks.replace).not.toHaveBeenCalled();
  });
});
