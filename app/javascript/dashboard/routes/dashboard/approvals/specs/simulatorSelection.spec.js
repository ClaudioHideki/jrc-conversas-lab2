import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { describe, it, expect } from 'vitest';
import en from 'dashboard/i18n/locale/en/jrcApprovals.json';
import pt from 'dashboard/i18n/locale/pt_BR/jrcApprovals.json';
import SimulatorView from '../SimulatorView.vue';

describe('Native simulator event identity across translations', () => {
  it.each(['en', 'pt_BR'])(
    'submits the catalog key, not its translated label, in %s',
    async language => {
      const wrapper = mount(SimulatorView, {
        props: {
          context: { account_id: 1, scopes: [] },
          catalogs: [{ key: 'crm.proposal_send', fields: {} }],
        },
        global: {
          plugins: [
            createI18n({
              legacy: false,
              locale: language,
              fallbackLocale: 'en',
              messages: { en, pt_BR: pt },
            }),
          ],
          stubs: {
            Button: {
              props: ['label', 'disabled'],
              template: '<button :disabled="disabled">{{ label }}</button>',
            },
            ResourcePicker: {
              emits: ['update:modelValue'],
              template:
                '<button data-source @click="$emit(\'update:modelValue\', 601)">Choose synthetic resource</button>',
            },
          },
        },
      });
      expect(wrapper.find('option[value="crm.proposal_send"]').exists()).toBe(
        true
      );
      await wrapper.find('select').setValue('crm.proposal_send');
      await wrapper.get('[data-source]').trigger('click');
      await flushPromises();
      await wrapper.findAll('button').at(-1).trigger('click');
      expect(wrapper.emitted('simulate')).toEqual([
        [{ key: 'crm.proposal_send', resource_id: 601 }],
      ]);
      wrapper.unmount();
    }
  );
});
