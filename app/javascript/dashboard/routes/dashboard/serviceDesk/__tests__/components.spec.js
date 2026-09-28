import { describe, it, expect } from 'vitest';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import PendingAction from '../components/PendingAction.vue';
import KpiCard from '../components/KpiCard.vue';
import State from '../components/ServiceDeskState.vue';
const i18n = () => createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: messages } });
const Button = { props: ['label', 'disabled'], template: '<button :disabled="disabled">{{ label }}</button>' };
const global = () => ({ plugins: [i18n()], stubs: { Button, Icon: true, Spinner: true } });
describe('CP3 presentation states (requires native Vue/Vitest)', () => {
  it('pending action stays disabled and reports unavailability, without emitting success', async () => {
    const wrapper = mount(PendingAction, { props: { label: 'Salvar' }, global: global() });
    expect(wrapper.find('button').attributes('disabled')).toBeDefined();
    expect(wrapper.text()).toContain(messages.JRC_SERVICE_DESK.COMMON.pending_cp4);
    await wrapper.find('button').trigger('click');
    expect(wrapper.emitted('success')).toBeUndefined();
  });
  it('KPI is unavailable, never a zero or an invented percentage', () => {
    const wrapper = mount(KpiCard, { props: { label: 'SLA' }, global: global() });
    expect(wrapper.find('strong').text()).toBe('\u2014');
    expect(wrapper.text()).not.toMatch(/\d/);
  });
  it('pending API and a real empty result have different messages', () => {
    const pending = mount(State, { props: { status: 'pending' }, global: global() });
    const empty = mount(State, { props: { status: 'empty' }, global: global() });
    expect(pending.text()).toContain(messages.JRC_SERVICE_DESK.STATES.pending_help);
    expect(empty.text()).not.toEqual(pending.text());
  });
  it('does not show retry while loading', () => {
    const wrapper = mount(State, { props: { status: 'loading', retry: true }, global: global() });
    expect(wrapper.find('button').exists()).toBe(false);
    expect(wrapper.attributes('aria-busy')).toBe('true');
  });
  it('a field-specific explanation is shown instead of a generic placeholder', () => {
    const wrapper = mount(State, { props: { status: 'pending', description: 'Endpoint de SLA pendente' }, global: global() });
    expect(wrapper.text()).toContain('Endpoint de SLA pendente');
  });
});
