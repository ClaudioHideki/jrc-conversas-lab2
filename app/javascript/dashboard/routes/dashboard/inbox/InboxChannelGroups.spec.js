import { mount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import InboxChannelGroups from './InboxChannelGroups.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) =>
      params?.label ? `${params.label} (${params.count})` : key,
  }),
}));
const inboxes = {
  11: {
    id: 11,
    name: 'Lucas — Support',
    channel_type: 'Channel::Whatsapp',
    phone_number: '+15550000001',
  },
  12: {
    id: 12,
    name: 'Ronald — Support',
    channel_type: 'Channel::Whatsapp',
    phone_number: '+15550000002',
  },
};
const conversation = (id, inbox, timestamp) => ({
  id,
  inbox_id: inbox,
  timestamp,
  messages: [],
  unread_count: 1,
  meta: {
    sender: { id: 7, name: 'Same customer', phone_number: '+15550000099' },
    assignee: { name: 'Ronald' },
  },
});
const render = (overrides = {}) =>
  mount(InboxChannelGroups, {
    props: {
      conversations: [
        conversation(1, 11, 10),
        conversation(2, 12, 15),
        conversation(3, 11, 20),
      ],
      inboxFor: item => inboxes[item.inbox_id],
      channels: [
        { key: 'email', label: 'Email' },
        { key: 'whatsapp', label: 'WhatsApp', icon: 'i-lucide-message-circle' },
      ],
      ...overrides,
    },
    global: {
      stubs: {
        ConversationCard: {
          props: ['chat', 'inbox'],
          template: '<div data-card :data-id="chat.id">{{ inbox.name }}</div>',
        },
      },
    },
  });

describe('conversation groups by source inbox', () => {
  it('keeps the same customer in distinct inboxes and identifies the source number independently of the assignee', () => {
    const wrapper = render();
    const groups = wrapper.findAll('section');
    expect(groups).toHaveLength(2);
    expect(groups[0].attributes('data-inbox-id')).toBe('11');
    expect(groups[0].text()).toContain('Lucas — Support');
    expect(groups[0].text()).toContain('+15550000001');
    expect(
      groups[0].findAll('[data-card]').map(card => card.attributes('data-id'))
    ).toEqual(['3', '1']);
    expect(groups[1].attributes('data-inbox-id')).toBe('12');
    expect(wrapper.text()).not.toContain('+15550000099');
  });

  it('does not merge inboxes with identical names or display unused empty channel sections', () => {
    const wrapper = render({
      inboxFor: item => ({ ...inboxes[item.inbox_id], name: 'Support' }),
    });
    expect(wrapper.findAll('section')).toHaveLength(2);
    expect(wrapper.find('[data-channel="voice"]').exists()).toBe(false);
  });

  it('retains independent collapse controls and selection emits the actual conversation', async () => {
    const wrapper = render();
    const first = wrapper.find('section');
    await first.find('button').trigger('click');
    expect(first.find('button').attributes('aria-expanded')).toBe('false');
    expect(
      wrapper.findAll('section')[1].find('button').attributes('aria-expanded')
    ).toBe('true');
    await wrapper.findAll('section')[1].find('[data-card]').trigger('click');
    expect(wrapper.emitted('selectConversation')[0][0].inbox_id).toBe(12);
  });

  it('preserves voice calls without fabricating a WhatsApp inbox for them', () => {
    const wrapper = render({
      conversations: [],
      calls: [{ id: 5, status: 'ringing', ani: 'synthetic-extension' }],
    });
    expect(wrapper.findAll('section')).toHaveLength(1);
    expect(wrapper.find('[data-channel="voice"]').exists()).toBe(true);
    expect(wrapper.text()).toContain('synthetic-extension');
  });
});
