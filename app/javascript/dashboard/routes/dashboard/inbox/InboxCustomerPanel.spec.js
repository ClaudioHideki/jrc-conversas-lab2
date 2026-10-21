import { describe, expect, it, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import InboxCustomerPanel from './InboxCustomerPanel.vue';
import InboxContextContent from './InboxContextContent.vue';
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: ref('pt_BR') }),
}));
const props = {
  accountId: 2,
  contact: {
    id: 22,
    name: 'Contact B',
    phone_number: '+550000000022',
    email: 'b@example.invalid',
  },
  company: {
    name: 'Company B',
    active: true,
    segment: 'Optical',
    owner_name: 'Owner B',
  },
  crm: {
    profile: { last_activity_at: '2026-10-16T12:00:00Z' },
    orders: [
      { id: 3, number: 'B-3', status: 'approved', deal: { title: 'Lenses B' } },
    ],
  },
  cases: [
    {
      id: 5,
      protocol: 'B-5',
      status: 'open',
      summary: 'Pending B',
      priority: 'high',
    },
  ],
  crmEnabled: true,
  interaction: { callSessionId: 8 },
};
const global = {
  stubs: {
    RouterLink: {
      name: 'RouterLink',
      props: ['to'],
      template: '<a><slot /></a>',
    },
  },
};
describe('existing customer 360 bridge', () => {
  it('keeps CRM order states and timeline dates readable in the contextual tabs', async () => {
    const wrapper = mount(InboxContextContent, {
      props: {
        tab: 'ORDERS',
        crm: {
          ...props.crm,
          timeline: [
            {
              id: 1,
              title: 'Return',
              user: 'Owner B',
              due_at: '2026-10-18T12:30:00Z',
            },
          ],
        },
      },
    });
    expect(wrapper.text()).toContain('CRM.STATUS.APPROVED');
    expect(wrapper.text()).not.toContain('approved');
    await wrapper.setProps({ tab: 'HISTORY' });
    expect(wrapper.text()).toContain('18/10/2026');
    expect(wrapper.text()).not.toContain('2026-10-18T');
    await wrapper.setProps({
      crm: { timeline: [{ id: 2, title: 'No date' }] },
    });
    expect(wrapper.text()).toContain('No date');
    expect(wrapper.text()).not.toContain('Invalid Date');
  });
  it('keeps drawer closing and the existing authorized WhatsApp route explicit', async () => {
    const whatsappTarget = {
      name: 'inbox_view_conversation',
      params: { accountId: 2, type: 'conversation', id: 202 },
      query: { assignee: 'me' },
    };
    const wrapper = mount(InboxCustomerPanel, {
      props: { ...props, closable: true, whatsappTarget },
      global,
    });
    const link = wrapper
      .findAllComponents({ name: 'RouterLink' })
      .find(
        item =>
          item.attributes('aria-label') ===
          'JRC_CONTACT_CENTER.INBOX_360.WHATSAPP'
      );
    expect(link.props('to')).toEqual(whatsappTarget);
    await wrapper
      .get('button[aria-label="DIALOG.BUTTONS.CANCEL"]')
      .trigger('click');
    expect(wrapper.emitted('close')).toHaveLength(1);
  });
  it('does not show canceled occurrences as open', () => {
    const wrapper = mount(InboxCustomerPanel, {
      props: {
        ...props,
        cases: [{ id: 8, protocol: 'CANCELED-8', status: 'canceled' }],
      },
      global,
    });
    expect(wrapper.text()).not.toContain('CANCELED-8');
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.INBOX_360.CASES_EMPTY'
    );
  });
  it('preserves the account, contact and call context in Ver 360', () => {
    const wrapper = mount(InboxCustomerPanel, { props, global });
    expect(wrapper.findComponent({ name: 'RouterLink' }).props('to')).toEqual({
      name: 'crm_customer_360',
      params: { accountId: 2, customerId: 22 },
      query: { callSessionId: 8 },
    });
    expect(wrapper.text()).toContain('Company B');
    expect(wrapper.text()).toContain('B-3');
    expect(wrapper.text()).toContain('B-5');
    expect(wrapper.text()).toContain('JRC_CONTACT_CENTER.INBOX_360.CRM_SOURCE');
  });
  it('keeps unavailable finance honest and switches between real contact/address data', async () => {
    const wrapper = mount(InboxCustomerPanel, {
      props: {
        ...props,
        addresses: [{ street: 'Local street', city: 'Curitiba', state: 'PR' }],
      },
      global,
    });
    const buttons = wrapper.find('nav').findAll('button');
    await buttons[1].trigger('click');
    expect(wrapper.text()).toContain('b@example.invalid');
    await buttons[2].trigger('click');
    expect(wrapper.text()).toContain('Local street');
    await buttons[3].trigger('click');
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.INBOX_360.FINANCE_EMPTY'
    );
  });
  it('does not offer CRM navigation when the feature is unavailable', () => {
    const wrapper = mount(InboxCustomerPanel, {
      props: { ...props, crmEnabled: false },
      global,
    });
    expect(wrapper.findComponent({ name: 'RouterLink' }).exists()).toBe(false);
  });
});
