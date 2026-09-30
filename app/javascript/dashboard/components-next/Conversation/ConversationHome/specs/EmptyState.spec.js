import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import EmptyState from 'dashboard/components/widgets/conversation/EmptyState/EmptyState.vue';
vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: true }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountScopedUrl: path => path }),
}));
vi.mock('../ConversationHome.vue', () => ({
  default: { template: '<div data-home />' },
}));
describe('conversation home preserves existing empty states', () => {
  it.each([
    [false, false, 1, true],
    [true, false, 1, false],
    [false, true, 1, false],
    [false, false, 0, false],
  ])(
    'expanded=%s loading=%s inboxes=%s shows home=%s',
    (expanded, loading, inboxCount, expected) => {
      const store = createStore({
        getters: {
          getSelectedChat: () => ({}),
          getAllConversations: () => [],
          'inboxes/getInboxes': () =>
            Array.from({ length: inboxCount }, () => ({ id: 1 })),
          'inboxes/getUIFlags': () => ({ isFetching: loading }),
          getChatListLoadingStatus: () => false,
        },
      });
      const wrapper = mount(EmptyState, {
        props: { isOnExpandedLayout: expanded },
        global: {
          plugins: [store],
          stubs: {
            OnboardingView: true,
            EmptyStateMessage: true,
            'woot-loading-state': true,
          },
        },
      });
      expect(wrapper.find('[data-home]').exists()).toBe(expected);
      if (!inboxCount)
        expect(wrapper.findComponent({ name: 'OnboardingView' }).exists()).toBe(
          true
        );
      wrapper.unmount();
    }
  );
});
