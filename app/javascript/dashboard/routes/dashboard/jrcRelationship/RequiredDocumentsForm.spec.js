import { mount } from '@vue/test-utils';
import { expect, it, vi } from 'vitest';
import Form from './RequiredDocumentsForm.vue';
import Field from './DocumentRequirementField.vue';
import Panel from './DocumentRequirementsPanel.vue';
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
const entry = {
  code: 'registration',
  title: 'Required registration',
  category: 'registration',
};
it('edits copies and supports explicit catalog addition and removal without mutating the server record', async () => {
  const original = [entry];
  const wrapper = mount(Form, { props: { modelValue: original } });
  await wrapper.findAll('input')[1].setValue('Updated registration');
  expect(original[0].title).toBe('Required registration');
  expect(wrapper.emitted('update:modelValue')[0][0][0].title).toBe(
    'Updated registration'
  );
  await wrapper.findAll('button')[1].trigger('click');
  expect(wrapper.emitted('update:modelValue').at(-1)[0]).toHaveLength(2);
  await wrapper.findAll('button')[0].trigger('click');
  expect(wrapper.emitted('update:modelValue').at(-1)[0]).toEqual([]);
  wrapper.unmount();
});
it('preserves the bounded catalog while saving or without edit permission', async () => {
  const wrapper = mount(Form, {
    props: { modelValue: [entry], disabled: true },
  });
  expect(
    wrapper.findAll('input, select, button').every(row => row.element.disabled)
  ).toBe(true);
  await wrapper.findAll('button')[0].trigger('click');
  expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  wrapper.unmount();
});
it('offers only matching categories and preserves an explicit historical link outside the current catalog', async () => {
  const wrapper = mount(Field, {
    props: {
      modelValue: 'old_requirement',
      category: 'registration',
      entries: [
        entry,
        { code: 'contract', title: 'Contract', category: 'contract' },
      ],
    },
  });
  expect(wrapper.get('select').element.value).toBe('old_requirement');
  expect(wrapper.find('option[value="contract"]').exists()).toBe(false);
  await wrapper.get('select').setValue('registration');
  expect(wrapper.emitted('update:modelValue')[0][0]).toBe('registration');
  await wrapper.get('select').setValue('');
  expect(wrapper.emitted('update:modelValue').at(-1)[0]).toBe('');
  wrapper.unmount();
});
it('shows native availability separately from legal approval and opens the exact existing document', async () => {
  const wrapper = mount(Panel, {
    props: {
      requirements: {
        scope_key: 'company:925',
        configuration_version: 2,
        entries: [{ ...entry, state: 'quarantined', document_id: 6 }],
      },
    },
  });
  expect(wrapper.text()).toContain(
    'RELATIONSHIP.V2.DOCS.REQUIREMENT_STATES.quarantined'
  );
  expect(wrapper.text()).toContain('RELATIONSHIP.V2.DOCS.FILE_NOT_APPROVAL');
  await wrapper.get('button').trigger('click');
  expect(wrapper.emitted('openDocument')[0]).toEqual([6]);
  wrapper.unmount();
});
