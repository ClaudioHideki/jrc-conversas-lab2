import { afterEach, describe, expect, it } from 'vitest';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import Template from '../NotificationWhatsappTemplate.vue';
const approved = {
  inbox_id: '7',
  fingerprint: 'a'.repeat(64),
  params: {
    name: 'synthetic',
    language: 'pt_BR',
    category: 'UTILITY',
    processed_params: { body: { 1: '{{number}}' } },
  },
  text: 'Chamado {{1}}',
};
let wrapper;
const render = (props = {}) => {
  wrapper = mount(Template, {
    props: { inbox: { id: '7', whatsapp_templates: [approved] }, ...props },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: messages },
        }),
      ],
    },
  });
  return wrapper;
};
afterEach(() => wrapper?.unmount());
describe('Explicit native WhatsApp template selection', () => {
  it('selects a copied approved identity and renders the configured source variable without mutating cached options', async () => {
    render();
    await wrapper.find('select').setValue(approved.fingerprint);
    const value = wrapper.emitted('update:modelValue')[0][0];
    expect(value).toEqual({
      inbox_id: '7',
      fingerprint: approved.fingerprint,
      params: approved.params,
    });
    expect(value.params).not.toBe(approved.params);
    expect(wrapper.emitted('selected')[0][0]).toEqual({
      content: 'Chamado {{number}}',
      version: 'synthetic:pt_BR',
    });
    expect(approved.params.processed_params.body['1']).toBe('{{number}}');
  });
  it('updates one parameter and preview while retaining the pinned identity', async () => {
    render({
      modelValue: {
        inbox_id: approved.inbox_id,
        fingerprint: approved.fingerprint,
        params: approved.params,
      },
    });
    await wrapper.find('input').setValue('{{status}}');
    expect(
      wrapper.emitted('update:modelValue')[0][0].params.processed_params.body[
        '1'
      ]
    ).toBe('{{status}}');
    expect(wrapper.emitted('selected')[0][0].content).toBe(
      'Chamado {{status}}'
    );
    expect(approved.params.processed_params.body['1']).toBe('{{number}}');
  });
  it('allows an explicit return to free text without silently approving anything', async () => {
    render({
      modelValue: {
        inbox_id: approved.inbox_id,
        fingerprint: approved.fingerprint,
        params: approved.params,
      },
    });
    await wrapper.find('select').setValue('');
    expect(wrapper.emitted('update:modelValue')[0][0]).toBeNull();
    expect(wrapper.emitted('selected')).toBeUndefined();
  });
  it('shows changed identity and keeps the selector disabled while a publication is pending', () => {
    render({ disabled: true, modelValue: { fingerprint: 'b'.repeat(64) } });
    expect(wrapper.find('select').element.disabled).toBe(true);
    expect(wrapper.text()).toContain('O template ou a caixa mudou');
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  });
});
