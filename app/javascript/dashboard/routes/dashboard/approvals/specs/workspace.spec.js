import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import locale from 'dashboard/i18n/locale/en/jrcApprovals.json';
import ApprovalInbox from '../ApprovalInbox.vue';
import ApprovalSummary from '../ApprovalSummary.vue';
import ApprovalStatus from '../ApprovalStatus.vue';

const global = () => ({
  plugins: [
    createI18n({ legacy: false, locale: 'en', messages: { en: locale } }),
  ],
  stubs: { Icon: true },
});
const request = {
  id: 7,
  policy_name: 'Authorized purchase',
  requester_name: 'Synthetic requester',
  state: 'pending',
  module_key: 'crm',
};

describe('Approval Word workspace', () => {
  it('shows unavailable indicators instead of inventing zero results', () => {
    const wrapper = mount(ApprovalSummary, { global: global() });
    expect(wrapper.findAll('[data-metric]')).toHaveLength(4);
    expect(wrapper.text()).toContain('—');
  });

  it('renders the server-authorized counts', () => {
    const wrapper = mount(ApprovalSummary, {
      global: global(),
      props: {
        summary: { pending: 12, approved: 8, rejected: 2, due_today: 3 },
      },
    });
    expect(wrapper.get('[data-metric="pending"]').text()).toContain('12');
    expect(wrapper.get('[data-metric="approved"]').text()).toContain('8');
  });

  it('opens only the selected authorized request and supports mobile return', async () => {
    const wrapper = mount(ApprovalInbox, {
      global: global(),
      props: { rows: [request], request, showDetail: true },
      slots: { detail: '<p>Existing authorized actions</p>' },
    });
    await wrapper.get('[data-approval-request="7"]').trigger('click');
    expect(wrapper.emitted('select')).toEqual([[7]]);
    expect(wrapper.text()).toContain('Existing authorized actions');
    await wrapper
      .findAll('button')
      .find(button =>
        button.text().includes(locale.JRC_APPROVALS.workspace.backToQueue)
      )
      .trigger('click');
    expect(wrapper.emitted('back')).toHaveLength(1);
  });

  it('does not fabricate commercial amounts or decision controls in the inbox', () => {
    const wrapper = mount(ApprovalInbox, {
      global: global(),
      props: { rows: [request] },
    });
    expect(wrapper.text()).toContain(request.policy_name);
    expect(wrapper.text()).not.toContain('R$');
    expect(wrapper.emitted('decide')).toBeUndefined();
  });

  it('localizes the request state without changing its value', () => {
    const wrapper = mount(ApprovalStatus, {
      global: global(),
      props: { state: 'pending' },
    });
    expect(wrapper.text()).toBe(locale.JRC_APPROVALS.workspace.states.pending);
  });
});
