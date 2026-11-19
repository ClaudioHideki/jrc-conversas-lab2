import { afterEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, mount } from '@vue/test-utils';
import AcwFormSchemaEditor from './AcwFormSchemaEditor.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
enableAutoUnmount(afterEach);
const row = (key = 'first') => ({
  key,
  label: 'SYNTHETIC field',
  type: 'text',
  required: false,
});
const mountEditor = (fields = [], extra = {}) =>
  mount(AcwFormSchemaEditor, { props: { modelValue: { fields }, ...extra } });

describe('native ACW field definition controls', () => {
  it('adds an explicitly optional field with a stable generated native key and no automatic request', async () => {
    const wrapper = mountEditor();
    expect(wrapper.emitted('ready').at(-1)).toEqual([false]);
    await wrapper.get('[data-add-acw-form-field]').trigger('click');
    const definition = wrapper.emitted('update:modelValue').at(-1)[0];
    expect(definition.fields[0]).toMatchObject({
      label: '',
      type: 'text',
      required: false,
    });
    expect(definition.fields[0].key).toMatch(/^[a-f0-9-]{36}$/);
    expect(wrapper.props('modelValue')).toEqual({ fields: [] });
  });

  it('edits the label without mutating the original version or regenerating its field key', async () => {
    const original = row();
    const wrapper = mountEditor([original]);
    await wrapper
      .get('[data-acw-schema-label]')
      .setValue('SYNTHETIC revised field');
    expect(wrapper.emitted('update:modelValue').at(-1)[0].fields[0]).toEqual({
      ...original,
      label: 'SYNTHETIC revised field',
    });
    expect(original.label).toBe('SYNTHETIC field');
  });

  it('switches a scalar to a selection with an explicit empty choice list requiring review', async () => {
    const wrapper = mountEditor([row()]);
    await wrapper.get('[data-acw-schema-type]').setValue('select');
    const definition = wrapper.emitted('update:modelValue').at(-1)[0];
    expect(definition.fields[0]).toEqual({
      ...row(),
      type: 'select',
      options: [],
    });
    await wrapper.setProps({ modelValue: definition });
    expect(wrapper.get('[data-acw-field-error]').text()).toContain(
      'FIELD_ERROR'
    );
    expect(wrapper.emitted('ready').at(-1)).toEqual([false]);
  });

  it('removes obsolete choice data when the configured field type changes', async () => {
    const original = { ...row(), type: 'select', options: ['first', 'second'] };
    const wrapper = mountEditor([original]);
    await wrapper.get('[data-acw-schema-type]').setValue('boolean');
    expect(wrapper.emitted('update:modelValue').at(-1)[0].fields[0]).toEqual({
      ...row(),
      type: 'boolean',
    });
    expect(original.options).toEqual(['first', 'second']);
  });

  it('retains duplicate and unfinished choice text while visibly blocking validation', async () => {
    const wrapper = mountEditor([
      { ...row(), type: 'select', options: ['first'] },
    ]);
    await wrapper.get('[data-acw-schema-options]').setValue('first\nfirst\n');
    const definition = wrapper.emitted('update:modelValue').at(-1)[0];
    expect(definition.fields[0].options).toEqual(['first', 'first', '']);
    await wrapper.setProps({ modelValue: definition });
    expect(wrapper.get('[data-acw-field-error]').exists()).toBe(true);
    expect(wrapper.emitted('ready').at(-1)).toEqual([false]);
  });

  it('marks a field required only after explicit user selection', async () => {
    const wrapper = mountEditor([row()]);
    await wrapper.get('[data-acw-schema-required]').setValue(true);
    expect(
      wrapper.emitted('update:modelValue').at(-1)[0].fields[0].required
    ).toBe(true);
    expect(wrapper.props('modelValue').fields[0].required).toBe(false);
  });

  it('reorders questions while preserving keys and the immutable input version', async () => {
    const fields = [row('first'), row('second')];
    const wrapper = mountEditor(fields);
    expect(
      wrapper.findAll('[data-acw-schema-up]')[0].attributes('disabled')
    ).toBeDefined();
    await wrapper.findAll('[data-acw-schema-down]')[0].trigger('click');
    expect(
      wrapper
        .emitted('update:modelValue')
        .at(-1)[0]
        .fields.map(field => field.key)
    ).toEqual(['second', 'first']);
    expect(fields.map(field => field.key)).toEqual(['first', 'second']);
  });

  it('removes only the chosen draft field and preserves the rest', async () => {
    const wrapper = mountEditor([row('first'), row('second')]);
    await wrapper.findAll('[data-acw-schema-remove]')[0].trigger('click');
    expect(
      wrapper
        .emitted('update:modelValue')
        .at(-1)[0]
        .fields.map(field => field.key)
    ).toEqual(['second']);
    expect(wrapper.props('modelValue').fields).toHaveLength(2);
  });

  it('does not allow a fifty-first question', async () => {
    const wrapper = mountEditor(
      Array.from({ length: 50 }, (_, i) => row(`field-${i}`))
    );
    expect(
      wrapper.get('[data-add-acw-form-field]').attributes('disabled')
    ).toBeDefined();
    await wrapper.get('[data-add-acw-form-field]').trigger('click');
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  });

  it('blocks editing, reordering and removing fields while the owner locks the operation', async () => {
    const wrapper = mountEditor([row('first'), row('second')], {
      disabled: true,
    });
    await wrapper
      .findAll('[data-acw-schema-label]')[0]
      .setValue('SYNTHETIC blocked');
    await wrapper.findAll('[data-acw-schema-down]')[0].trigger('click');
    await wrapper.findAll('[data-acw-schema-remove]')[0].trigger('click');
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  });
});
