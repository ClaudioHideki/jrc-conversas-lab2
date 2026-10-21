import { shallowMount } from '@vue/test-utils';
import ConversationCard from '../ConversationCard.vue';

const defaultChat = {
  id: 1,
  labels: [],
  messages: [],
  priority: null,
  unread_count: 0,
  timestamp: 1700000000,
  created_at: 1700000000,
};

const mountComponent = (chat, currentContact = {}) =>
  shallowMount(ConversationCard, {
    props: {
      chat: { ...defaultChat, ...chat },
      currentContact: {
        name: 'Jane Doe',
        thumbnail: '',
        availability_status: 'offline',
        ...currentContact,
      },
      inbox: { id: 1 },
    },
    global: {
      stubs: {
        'fluent-icon': true,
      },
    },
  });

describe('ConversationCard', () => {
  it('keeps the default card and offers a dense operational presentation without reserving name space for the clock', async () => {
    const wrapper = mountComponent({});
    expect(wrapper.get('.conversation--user').classes()).toContain('ltr:pr-16');
    await wrapper.setProps({
      operational: true,
      compact: true,
      showAssignee: true,
      assignee: { name: 'Assigned operator' },
    });
    expect(wrapper.get('.conversation--user').classes()).not.toContain(
      'ltr:pr-16'
    );
    expect(wrapper.text()).toContain('Jane Doe');
    expect(wrapper.text()).toContain('Assigned operator');
    expect(wrapper.findComponent({ name: 'TimeAgo' }).exists()).toBe(true);
  });
  it('does not reserve the labels row when only a persisted SLA policy id is present', () => {
    const wrapper = mountComponent({ sla_policy_id: 1, applied_sla: null });

    expect(wrapper.findComponent({ name: 'CardLabels' }).exists()).toBe(false);
  });

  it('shows the labels row when an active applied SLA is present', () => {
    const wrapper = mountComponent({
      sla_policy_id: 1,
      applied_sla: { id: 1 },
    });

    expect(wrapper.findComponent({ name: 'CardLabels' }).exists()).toBe(true);
  });

  it('does not reserve the labels row when the contact is blocked', () => {
    const wrapper = mountComponent(
      {
        sla_policy_id: 1,
        applied_sla: { id: 1 },
      },
      { blocked: true }
    );

    expect(wrapper.findComponent({ name: 'CardLabels' }).exists()).toBe(false);
  });
});
