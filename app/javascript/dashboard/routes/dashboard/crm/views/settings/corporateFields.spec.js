import { describe, it, expect } from 'vitest';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/crm.json';
import CorporateProfileFields from './CorporateProfileFields.vue';
import CommercialGratuityFields from '../proposals/CommercialGratuityFields.vue';
const plugins = () => [
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: messages } }),
];

describe('Corporate profile and gratuity declaration forms', () => {
  it('keeps legal and fiscal details pending instead of inventing official values', () => {
    const wrapper = mount(CorporateProfileFields, {
      props: { modelValue: {}, users: [] },
      global: { plugins: plugins() },
    });
    expect(
      wrapper.findAll('input').every(input => input.element.value === '')
    ).toBe(true);
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    expect(wrapper.text()).toContain(messages.CRM.CORPORATE.PENDING_NOTE);
    wrapper.unmount();
  });

  it('uses a native account-user identity without changing the source profile', async () => {
    const original = { legal_name: null };
    const wrapper = mount(CorporateProfileFields, {
      props: {
        modelValue: original,
        users: [{ account_user_id: 42, name: 'Synthetic Jose' }],
      },
      global: { plugins: plugins() },
    });
    await wrapper.findAll('select')[1].setValue('42');
    expect(wrapper.emitted('update:modelValue')[0][0]).toEqual({
      legal_name: null,
      commercial_gratuity_principal_id: 42,
    });
    expect(original).toEqual({ legal_name: null });
    wrapper.unmount();
  });

  it('prepares only an explicit typed declaration and keeps its reason required', async () => {
    const wrapper = mount(CommercialGratuityFields, {
      props: { modelValue: {} },
      global: { plugins: plugins() },
    });
    await wrapper.get('select').setValue('installation');
    const intent = wrapper.emitted('update:modelValue')[0][0];
    expect(intent).toEqual({ type: 'installation', reason: '' });
    await wrapper.setProps({ modelValue: intent });
    expect(wrapper.get('input').attributes('required')).toBeDefined();
    await wrapper.get('input').setValue('Synthetic commercial exception');
    expect(wrapper.emitted('update:modelValue').at(-1)[0]).toEqual({
      type: 'installation',
      reason: 'Synthetic commercial exception',
    });
    expect(wrapper.text()).toContain(messages.CRM.GRATUITY.HELP);
    wrapper.unmount();
  });

  it('honors the busy state without sending, publishing or granting permissions', () => {
    const wrapper = mount(CommercialGratuityFields, {
      props: { modelValue: {}, disabled: true },
      global: { plugins: plugins() },
    });
    expect(wrapper.get('fieldset').attributes('disabled')).toBeDefined();
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    wrapper.unmount();
  });
});
