import { shallowMount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import NotificationTable from './NotificationTable.vue';

describe('native notification table compatibility', () => {
  it.each(['JrcApprovals::Request', 'JrcApprovals::AuditEvent'])(
    'renders and opens a bounded %s actor without conversation metadata',
    actorType => {
      const notice = {
        id: 1,
        notification_type: 'approval_event',
        primary_actor_type: actorType,
        primary_actor: { id: 123, account_id: 1, meta: {} },
        read_at: null,
        last_activity_at: 1793800000,
        push_message_title: 'Approval update',
      };
      const click = vi.fn();
      const wrapper = shallowMount(NotificationTable, {
        props: { notifications: [notice], onClickNotification: click },
        global: {
          mocks: {
            $store: {
              getters: { 'notifications/getMeta': { unreadCount: 1 } },
            },
          },
        },
      });
      expect(wrapper.text()).toContain('Approval update');
      expect(wrapper.text()).toContain('#123');
      expect(wrapper.findComponent({ name: 'Avatar' }).exists()).toBe(false);
      wrapper.get('tbody tr').trigger('click');
      expect(click).toHaveBeenCalledWith(notice);
      wrapper.unmount();
    }
  );
});
