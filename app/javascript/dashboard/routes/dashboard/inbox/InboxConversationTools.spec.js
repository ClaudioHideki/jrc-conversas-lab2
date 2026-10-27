import { ref } from 'vue';
import { createStore } from 'vuex';
import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import InboxConversationTools from './InboxConversationTools.vue';

const { widget } = vi.hoisted(() => ({
  widget: name => ({
    name,
    props: [
      'conversationId',
      'contactId',
      'inboxId',
      'embedded',
      'conversationAttributes',
      'contactAttributes',
      'attributeType',
    ],
    template: '<div data-native-widget />',
  }),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('../conversation/ConversationAction.vue', () => ({
  default: widget('ConversationAction'),
}));
vi.mock('../conversation/Macros/List.vue', () => ({
  default: widget('MacrosList'),
}));
vi.mock('../conversation/ConversationInfo.vue', () => ({
  default: widget('ConversationInfo'),
}));
vi.mock('../conversation/customAttributes/CustomAttributes.vue', () => ({
  default: widget('CustomAttributes'),
}));
vi.mock('../conversation/contact/ContactNotes.vue', () => ({
  default: widget('ContactNotes'),
}));
vi.mock('../conversation/SharedFiles.vue', () => ({
  default: widget('SharedFiles'),
}));
vi.mock('../conversation/ContactConversations.vue', () => ({
  default: widget('ContactConversations'),
}));
vi.mock('../conversation/ConversationParticipant.vue', () => ({
  default: widget('ConversationParticipant'),
}));
enableAutoUnmount(afterEach);

const chat = ref({
  id: 21,
  account_id: 1,
  inbox_id: 3,
  meta: { sender: { id: 75 } },
});
const macrosEnabled = ref(true);
const store = createStore({
  getters: {
    getSelectedChat: () => chat.value,
    getSelectedChatAttachmentsLoaded: () => false,
    'contacts/getContact': () => () => ({
      id: 75,
      additional_attributes: { marker: 'synthetic' },
    }),
    'conversationMetadata/getConversationMetadata': () => () => ({
      additional_attributes: { referer: 'https://synthetic.invalid/' },
    }),
    'accounts/isFeatureEnabledonAccount': () => () => macrosEnabled.value,
  },
});
let dispatch;
beforeEach(() => {
  chat.value = {
    id: 21,
    account_id: 1,
    inbox_id: 3,
    meta: { sender: { id: 75 } },
  };
  macrosEnabled.value = true;
  dispatch = vi.spyOn(store, 'dispatch').mockResolvedValue(undefined);
});
afterEach(() => vi.restoreAllMocks());

it.each([
  [
    'conversation_actions',
    'ConversationAction',
    { conversationId: 21, inboxId: 3 },
  ],
  ['macros', 'MacrosList', { conversationId: 21 }],
  [
    'conversation_info',
    'ConversationInfo',
    {
      conversationAttributes: { referer: 'https://synthetic.invalid/' },
      contactAttributes: { marker: 'synthetic' },
    },
  ],
  [
    'contact_attributes',
    'CustomAttributes',
    { contactId: 75, attributeType: 'contact_attribute' },
  ],
  ['contact_notes', 'ContactNotes', { contactId: 75 }],
  ['shared_files', 'SharedFiles', {}],
  [
    'previous_conversation',
    'ContactConversations',
    { contactId: 75, conversationId: 21, embedded: true },
  ],
  [
    'conversation_participants',
    'ConversationParticipant',
    { conversationId: 21 },
  ],
])(
  'uses the native widget for %s with the selected identifiers',
  async (tool, name, expectedProps) => {
    const wrapper = mount(InboxConversationTools, {
      props: { accountId: 1, conversationId: 21, tool },
      global: { plugins: [store] },
    });
    await flushPromises();
    expect(wrapper.getComponent({ name }).props()).toMatchObject(expectedProps);
    expect(
      dispatch.mock.calls.every(
        ([action]) => !/create|update|delete|assign|send/i.test(action)
      )
    ).toBe(true);
    if (tool === 'shared_files')
      expect(dispatch).toHaveBeenCalledWith('fetchAllAttachments', 21);
  }
);

it('does not mount native widgets or request data for a stale conversation from another Account', async () => {
  const wrapper = mount(InboxConversationTools, {
    props: { accountId: 2, conversationId: 21, tool: 'contact_notes' },
    global: { plugins: [store] },
  });
  await flushPromises();
  expect(wrapper.find('[data-native-widget]').exists()).toBe(false);
  expect(dispatch).not.toHaveBeenCalled();
});

it('preserves the macros feature flag and never fetches disabled macros', async () => {
  macrosEnabled.value = false;
  const wrapper = mount(InboxConversationTools, {
    props: { accountId: 1, conversationId: 21, tool: 'macros' },
    global: { plugins: [store] },
  });
  await flushPromises();
  expect(wrapper.find('[data-native-widget]').exists()).toBe(false);
  expect(dispatch).not.toHaveBeenCalled();
});

it('reuses contact details between information and attributes and presents an explicit retry on a denied read', async () => {
  dispatch.mockRejectedValueOnce(new Error('Denied synthetic read'));
  const wrapper = mount(InboxConversationTools, {
    props: { accountId: 1, conversationId: 21, tool: 'conversation_info' },
    global: { plugins: [store] },
  });
  await flushPromises();
  expect(wrapper.get('[role="alert"]').text()).toContain(
    'JRC_CONTACT_CENTER.COMMON.ERROR'
  );
  expect(wrapper.find('[data-native-widget]').exists()).toBe(false);
  await wrapper.get('[role="alert"] button').trigger('click');
  await flushPromises();
  expect(wrapper.findComponent({ name: 'ConversationInfo' }).exists()).toBe(
    true
  );
  const reads = dispatch.mock.calls.filter(
    ([action]) => action === 'contacts/show'
  ).length;
  await wrapper.setProps({ tool: 'contact_attributes' });
  await flushPromises();
  expect(wrapper.findComponent({ name: 'CustomAttributes' }).exists()).toBe(
    true
  );
  expect(
    dispatch.mock.calls.filter(([action]) => action === 'contacts/show')
  ).toHaveLength(reads);
});
