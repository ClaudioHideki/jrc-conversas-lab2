import { shallowMount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import NotificationsView from './NotificationsView.vue';

vi.mock('dashboard/composables', () => ({ useTrack: vi.fn() }));
vi.mock('./NotificationTable.vue', () => ({
  default: {
    name: 'NotificationTable',
    props: ['onClickNotification'],
    template: '<div />',
  },
}));
vi.mock('dashboard/components/widgets/TableFooter.vue', () => ({
  default: { name: 'TableFooter', template: '<div />' },
}));

const notification = {
  id: 9,
  notification_type: 'approval_event',
  account_id: 1,
  primary_actor_type: 'JrcApprovals::Request',
  primary_actor_id: 23,
  primary_actor: { id: 23, account_id: 1, meta: {} },
};

describe('native notification view approval interaction', () => {
  it.each([1, 2])(
    'opens the exact native CS case only for its current account%s',
    accountId => {
      const dispatch = vi.fn();
      const push = vi.fn();
      const source = {
        id: 12,
        notification_type: 'relationship_action',
        account_id: 1,
        primary_actor_type: 'JrcRelationship::Action',
        primary_actor_id: 34,
        primary_actor: { id: 34, assignment_id: 56 },
      };
      const wrapper = shallowMount(NotificationsView, {
        global: {
          mocks: {
            $store: {
              dispatch,
              getters: {
                getCurrentAccountId: accountId,
                'notifications/getMeta': {
                  unreadCount: 3,
                  currentPage: 1,
                  count: 1,
                },
                'notifications/getNotifications': [source],
                'notifications/getUIFlags': {
                  isFetching: false,
                  isUpdating: false,
                },
              },
            },
            $router: { push },
            $route: { path: `/app/accounts/${accountId}/notifications` },
          },
        },
      });
      wrapper
        .findComponent({ name: 'NotificationTable' })
        .props('onClickNotification')(source);
      if (accountId === 1) {
        expect(dispatch).toHaveBeenCalledWith(
          'notifications/read',
          expect.objectContaining({ id: 12, primaryActorId: 34 })
        );
        expect(push).toHaveBeenCalledWith({
          name: 'jrc_relationship_actions',
          params: { accountId: 1 },
          query: { assignment_id: 56, action_id: 34 },
        });
      } else {
        expect(dispatch).not.toHaveBeenCalledWith(
          'notifications/read',
          expect.anything()
        );
        expect(push).not.toHaveBeenCalled();
      }
      wrapper.unmount();
    }
  );
  it.each([1, 2])(
    'handles a notification while account %s is active',
    accountId => {
      const dispatch = vi.fn();
      const push = vi.fn();
      const wrapper = shallowMount(NotificationsView, {
        global: {
          mocks: {
            $store: {
              dispatch,
              getters: {
                getCurrentAccountId: accountId,
                'notifications/getMeta': {
                  unreadCount: 3,
                  currentPage: 1,
                  count: 1,
                },
                'notifications/getNotifications': [notification],
                'notifications/getUIFlags': {
                  isFetching: false,
                  isUpdating: false,
                },
              },
            },
            $router: { push },
            $route: { path: `/app/accounts/${accountId}/notifications` },
          },
        },
      });
      wrapper
        .findComponent({ name: 'NotificationTable' })
        .props('onClickNotification')(notification);
      if (accountId === 1) {
        expect(dispatch).toHaveBeenCalledWith('notifications/read', {
          id: 9,
          primaryActorId: 23,
          primaryActorType: 'JrcApprovals::Request',
          unreadCount: 3,
        });
        expect(push).toHaveBeenCalledWith({
          name: 'jrc_approvals',
          params: { accountId: 1, screen: 'inbox', id: 23 },
        });
      } else {
        expect(dispatch).not.toHaveBeenCalledWith(
          'notifications/read',
          expect.anything()
        );
        expect(push).not.toHaveBeenCalled();
      }
      wrapper.unmount();
    }
  );
});
