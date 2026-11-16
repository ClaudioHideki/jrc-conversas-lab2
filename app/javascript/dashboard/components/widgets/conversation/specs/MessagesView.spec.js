import { shallowMount } from '@vue/test-utils';
import MessagesView from '../MessagesView.vue';

describe('MessagesView publication clock', () => {
  it('passes the delayed newly published message as the first unread divider without reordering messages', () => {
    const messages = [
      { id: 1, message_type: 0, created_at: 100, broker_published_at: 300 },
      { id: 2, message_type: 0, created_at: 200 },
    ];
    const wrapper = shallowMount(
      {
        ...MessagesView,
        setup: () => ({}),
        created: [],
        mounted: [],
        unmounted: [],
        computed: {
          ...MessagesView.computed,
          currentChat: () => ({
            id: 1,
            agent_last_seen_at: 250,
            messages,
            can_reply: true,
          }),
          currentUserId: () => 1,
          currentAccountId: () => 1,
          isAnEmailChannel: () => false,
          inboxSupportsReplyTo: () => ({ incoming: false, outgoing: false }),
          getMessages: () => messages,
          shouldShowSpinner: () => false,
          shouldShowLabelSuggestions: () => false,
          replyWindowBannerMessage: () => '',
          hasDuplicateInstagramInbox: () => false,
          inbox: () => ({}),
          typingUsersList: () => [],
        },
      },
      { global: { mocks: { $store: { getters: {}, dispatch: vi.fn() } } } }
    );
    expect(wrapper.vm.readMessages.map(message => message.id)).toEqual([2]);
    expect(wrapper.vm.unReadMessages.map(message => message.id)).toEqual([1]);
    expect(
      wrapper.findComponent({ name: 'MessageList' }).props('firstUnreadId')
    ).toBe(1);
    expect(wrapper.vm.getMessages).toEqual(messages);
    wrapper.unmount();
  });
});
