import { mount } from '@vue/test-utils';
import { describe, expect, it } from 'vitest';
import InboxOriginLabel from './InboxOriginLabel.vue';

describe('source identity for the selected conversation', () => {
  it('stops presenting a Broker number as verified when its cached proof expires', async () => {
    const wrapper = mount(InboxOriginLabel, {
      props: {
        now: Date.parse('2026-11-05T12:01:00Z'),
        inbox: {
          id: 11,
          name: 'Lucas',
          channel_type: 'Channel::Api',
          jrc_broker_bound: true,
          conversation_origin: {
            own_number: '+15550000001',
            number_status: 'VERIFIED',
            verified_at: '2026-11-05T12:00:00Z',
            valid_until: '2026-11-05T12:15:00Z',
          },
        },
      },
    });
    expect(wrapper.text()).toContain('+15550000001');
    await wrapper.setProps({ now: Date.parse('2026-11-05T12:15:00Z') });
    expect(wrapper.text()).not.toContain('+15550000001');
    expect(wrapper.text()).toContain('Número a confirmar');
  });
  it('shows the actual inbox and business number for receiving and replying without offering another sender', async () => {
    const wrapper = mount(InboxOriginLabel, {
      props: {
        inbox: {
          id: 11,
          name: 'Lucas — Support',
          channel_type: 'Channel::Whatsapp',
          phone_number: '+15550000001',
        },
      },
    });
    expect(wrapper.text()).toContain('Lucas — Support');
    expect(wrapper.text()).toContain('+15550000001');
    expect(wrapper.text()).toContain('Recebido em:');
    await wrapper.setProps({ reply: true });
    expect(wrapper.text()).toContain('Responder por:');
    expect(wrapper.find('select').exists()).toBe(false);
  });
  it('renders an unknown Broker identity without using a phone number from the customer or configuration', () => {
    const wrapper = mount(InboxOriginLabel, {
      props: {
        inbox: {
          id: 12,
          name: 'Ronald — Support',
          channel_type: 'Channel::Api',
          jrc_broker_bound: true,
          provider_config: { phone: '+15550000099' },
        },
      },
    });
    expect(wrapper.text()).toContain('Ronald — Support');
    expect(wrapper.text()).toContain('Número a confirmar');
    expect(wrapper.text()).not.toContain('+15550000099');
  });
});
