import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import InboxList from '../InboxList.vue';

vi.mock('vue-router', () => ({
  useRoute: () => ({ query: { channel: 'whatsapp' }, params: {} }),
  useRouter: () => ({ replace: vi.fn(), push: vi.fn() }),
}));
vi.mock(
  'dashboard/components/widgets/conversation/ConversationCard.vue',
  () => ({
    default: {
      props: ['chat'],
      template: '<div data-test="conversation">{{ chat.id }}</div>',
    },
  })
);

describe('InboxList channel pagination', () => {
  it.each([0, 2])(
    'keeps subsequent pages reachable with only %s WhatsApp matches',
    async matches => {
      const inboxes = [
        { id: 1, channel_type: 'Channel::Whatsapp' },
        { id: 2, channel_type: 'Channel::Email' },
      ];
      const store = createStore({
        state: {
          rows: Array.from({ length: 25 }, (_, index) => ({
            id: index + 1,
            inbox_id: index < matches ? 1 : 2,
          })),
          ended: false,
        },
        getters: {
          'inboxes/getAllInboxes': () => inboxes,
          'inboxes/getInboxById': () => id =>
            inboxes.find(inbox => inbox.id === id),
          getAllStatusChats: state => () => state.rows,
          getChatListLoadingStatus: () => false,
          'conversationPage/getHasEndReached': state => () => state.ended,
        },
      });
      const dispatch = vi.spyOn(store, 'dispatch').mockResolvedValue();
      const wrapper = mount(InboxList, {
        global: {
          plugins: [store],
          stubs: {
            RouterLink: { template: '<a><slot /></a>' },
            RouterView: true,
            Spinner: true,
          },
        },
      });
      await flushPromises();
      expect(wrapper.findAll('[data-test="conversation"]')).toHaveLength(
        matches
      );
      const loadMore = wrapper
        .findAll('button')
        .find(button => button.text() === 'Carregar mais conversas');
      expect(loadMore).toBeDefined();
      await loadMore.trigger('click');
      expect(dispatch).toHaveBeenCalledWith(
        'updateChatListFilters',
        expect.objectContaining({ page: 2 })
      );
      store.state.rows.push({ id: 26, inbox_id: 1 });
      await flushPromises();
      expect(wrapper.findAll('[data-test="conversation"]')).toHaveLength(
        matches + 1
      );
      store.state.ended = true;
      await flushPromises();
      expect(
        wrapper
          .findAll('button')
          .some(button => button.text() === 'Carregar mais conversas')
      ).toBe(false);
      wrapper.unmount();
    }
  );
});
