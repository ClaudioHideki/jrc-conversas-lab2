import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive } from 'vue';
import { createStore } from 'vuex';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { emitter } from 'shared/helpers/mitt';
import InboxView from './InboxView.vue';

const mocks = vi.hoisted(() => ({ route: null }));
vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRoute: () => mocks.route,
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings: { value: { is_contact_sidebar_open: true } },
  }),
}));
enableAutoUnmount(afterEach);
let store;
let getConversation;
let setActiveChat;
const conversation = {
  id: 101,
  account_id: 1,
  messages: [{ id: 1 }],
  meta: {},
};
const global = {
  stubs: {
    ConversationBox: {
      name: 'ConversationBox',
      props: ['hideHeader'],
      template: '<div data-testid="native-conversation" />',
    },
    ConversationSidebar: true,
    InboxEmptyState: true,
    SidepanelSwitch: true,
    Spinner: true,
  },
};
describe('native embedded conversation selection', () => {
  beforeEach(() => {
    mocks.route = reactive({ params: { accountId: '1', id: '101' } });
    getConversation = vi.fn();
    setActiveChat = vi.fn(({ state }, { data }) => {
      state.chat = data;
    });
    store = createStore({
      state: () => ({ records: [], chat: {} }),
      getters: {
        getSelectedChat: state => state.chat,
        getConversationById: state => id =>
          state.records.find(item => item.id === id),
      },
      actions: {
        getConversation,
        setActiveChat,
        clearSelectedState: ({ state }) => {
          state.chat = {};
        },
        'agents/get': vi.fn(),
      },
    });
    vi.spyOn(emitter, 'emit');
  });
  it('uses the native conversation and hides only its duplicate header/sidebar when embedded', async () => {
    store.state.records = [conversation];
    const wrapper = mount(InboxView, {
      props: { embedded: true },
      global: { ...global, plugins: [store] },
    });
    await flushPromises();
    expect(getConversation).not.toHaveBeenCalled();
    expect(setActiveChat).toHaveBeenCalled();
    expect(
      wrapper.findComponent({ name: 'ConversationBox' }).props('hideHeader')
    ).toBe(true);
    expect(
      wrapper.findComponent({ name: 'ConversationSidebar' }).exists()
    ).toBe(false);
    expect(wrapper.find('[data-testid="native-conversation"]').exists()).toBe(
      true
    );
  });
  it('shows an error instead of a blank workspace when the existing API does not return an authorized conversation', async () => {
    getConversation.mockResolvedValue(undefined);
    const wrapper = mount(InboxView, {
      props: { embedded: true },
      global: { ...global, plugins: [store] },
    });
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toBe(
      'JRC_CONTACT_CENTER.COMMON.ERROR'
    );
    expect(setActiveChat).not.toHaveBeenCalled();
  });
  it('does not select or scroll a conversation returned after unmount', async () => {
    let resolveOld;
    getConversation.mockImplementation(
      () =>
        new Promise(resolve => {
          resolveOld = resolve;
        })
    );
    const wrapper = mount(InboxView, {
      props: { embedded: true },
      global: { ...global, plugins: [store] },
    });
    await flushPromises();
    wrapper.unmount();
    store.state.records = [conversation];
    resolveOld();
    await flushPromises();
    expect(setActiveChat).not.toHaveBeenCalled();
    expect(emitter.emit).not.toHaveBeenCalled();
  });
  it('keeps the new selection when the previous route responds late', async () => {
    let resolveOld;
    getConversation.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOld = resolve;
        })
    );
    mount(InboxView, {
      props: { embedded: true },
      global: { ...global, plugins: [store] },
    });
    await flushPromises();
    store.state.records = [{ ...conversation, id: 202 }];
    mocks.route.params.id = '202';
    await flushPromises();
    store.state.records.push(conversation);
    resolveOld();
    await flushPromises();
    expect(store.state.chat.id).toBe(202);
    expect(setActiveChat).toHaveBeenCalledTimes(1);
    expect(emitter.emit).toHaveBeenCalledTimes(1);
  });
});
