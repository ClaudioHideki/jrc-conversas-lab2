import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { expect, it, vi } from 'vitest';
import messages from 'dashboard/i18n/locale/en/crm.json';
import Card from './ContractRenewalCard.vue';
vi.mock('../useCustomerMaster', () => ({ useCustomerMaster: () => ({ accountScopedRoute: (name, params, query) => ({ name, params: { accountId: '1', ...params }, query }) }) }));
const Link = { props: ['to'], template: '<a><slot /></a>' };
const render = value => mount(Card, { props: { value }, global: { plugins: [createI18n({ legacy: false, locale: 'en', messages: { en: messages } })], stubs: { RouterLink: Link } } });
it('opens the exact native contract with date-only presentation and does not offer an automatic renewal', () => {
 const wrapper = render({ next: { id: 42, contract_number: 'SYNTHETIC-42', ends_on: '2026-12-01', notice_on: '2026-11-01', within_notice_window: true }, overdue: 2, undated: 1 });
 expect(wrapper.findComponent(Link).props('to')).toEqual({ name: 'crm_contracts', params: { accountId: '1' }, query: { contractId: 42 } });
 expect(wrapper.text()).toContain('01/12/2026'); expect(wrapper.find('button').exists()).toBe(false); wrapper.unmount();
});
it('shows no upcoming date without inventing a renewal or hiding overdue and undated contracts', () => {
 const wrapper = render({ next: null, overdue: 1, undated: 2 }); expect(wrapper.find('a').exists()).toBe(false); expect(wrapper.text()).toContain('Sem contrato'); expect(wrapper.text()).toContain('vencido'); expect(wrapper.text()).toContain('sem data'); wrapper.unmount();
});
