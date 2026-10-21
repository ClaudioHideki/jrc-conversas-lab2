import { createRouter, createMemoryHistory } from 'vue-router';
import conversations from '../conversation.routes';

vi.mock('../ConversationView.vue', () => ({
  default: { template: '<div />' },
}));
vi.mock('dashboard/store', () => ({
  default: { getters: {}, dispatch: vi.fn() },
}));

describe('unified attendance entry routes', () => {
  it.each([
    [
      '/app/accounts/7/dashboard?assignee=all',
      'inbox_view',
      { accountId: '7' },
    ],
    [
      '/app/accounts/7/conversations/31?assignee=me',
      'inbox_view_conversation',
      { accountId: '7', type: 'conversation', id: '31' },
    ],
  ])(
    'routes the existing URL %s to the HOYA workspace',
    async (url, name, params) => {
      const router = createRouter({
        history: createMemoryHistory(),
        routes: [
          ...conversations.routes,
          {
            path: '/app/accounts/:accountId/inbox-view',
            name: 'inbox_view',
            component: { template: '<div />' },
          },
          {
            path: '/app/accounts/:accountId/inbox-view/:type/:id',
            name: 'inbox_view_conversation',
            component: { template: '<div />' },
          },
        ],
      });
      await router.push(url);
      expect(router.currentRoute.value.name).toBe(name);
      expect(router.currentRoute.value.params).toEqual(params);
      expect(router.currentRoute.value.query.assignee).toBe(
        url.includes('=all') ? 'all' : 'me'
      );
    }
  );

  it('keeps inbox and label contexts and their existing permission guards', () => {
    [
      'inbox_dashboard',
      'conversation_through_inbox',
      'label_conversations',
      'conversations_through_label',
    ].forEach(name => {
      const route = conversations.routes.find(item => item.name === name);
      expect(route.redirect).toBeUndefined();
      expect(route.meta.permissions).toContain('conversation_manage');
    });
  });
});
