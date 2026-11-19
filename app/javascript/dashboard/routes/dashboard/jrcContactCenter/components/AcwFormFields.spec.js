import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, mount } from '@vue/test-utils';
import AcwFormFields from './AcwFormFields.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
enableAutoUnmount(afterEach);
let definition;
let answers;
beforeEach(() => {
  definition = {
    fields: [
      {
        key: 'detail',
        label: 'SYNTHETIC private detail',
        type: 'text',
        required: true,
      },
      {
        key: 'count',
        label: 'SYNTHETIC count',
        type: 'integer',
        required: true,
      },
      {
        key: 'confirmed',
        label: 'SYNTHETIC confirmation',
        type: 'boolean',
        required: true,
      },
      {
        key: 'result',
        label: 'SYNTHETIC result',
        type: 'select',
        required: true,
        options: ['first', 'second'],
      },
    ],
  };
  answers = {
    detail: 'SYNTHETIC text',
    count: 0,
    confirmed: false,
    result: 'first',
  };
});
const mountFields = (modelValue = {}, extra = {}) =>
  mount(AcwFormFields, { props: { definition, modelValue, ...extra } });

describe('ACW fields with explicit typed answers', () => {
  it('renders labeled native controls without treating an untouched boolean as false', () => {
    const wrapper = mountFields();
    expect(wrapper.findAll('label')).toHaveLength(4);
    expect(wrapper.findAll('input[type="checkbox"]')).toHaveLength(0);
    expect(wrapper.get('[data-acw-answer="confirmed"]').element.value).toBe('');
    expect(wrapper.emitted('ready').at(-1)).toEqual([false]);
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  });

  it('accepts explicit no and zero as complete values and preserves their display', () => {
    const wrapper = mountFields(answers);
    expect(wrapper.get('[data-acw-answer="confirmed"]').element.value).toBe(
      'false'
    );
    expect(wrapper.get('[data-acw-answer="count"]').element.value).toBe('0');
    expect(wrapper.emitted('ready').at(-1)).toEqual([true]);
  });

  it('emits a typed negative boolean only after a deliberate choice', async () => {
    delete answers.confirmed;
    const wrapper = mountFields(answers);
    expect(wrapper.emitted('ready').at(-1)).toEqual([false]);
    await wrapper.get('[data-acw-answer="confirmed"]').setValue('false');
    const updated = wrapper.emitted('update:modelValue').at(-1)[0];
    expect(updated.confirmed).toBe(false);
    expect(Object.hasOwn(answers, 'confirmed')).toBe(false);
    await wrapper.setProps({ modelValue: updated });
    expect(wrapper.emitted('ready').at(-1)).toEqual([true]);
  });

  it('keeps an explicitly cleared boolean unanswered without converting it into no', async () => {
    const wrapper = mountFields(answers);
    await wrapper.get('[data-acw-answer="confirmed"]').setValue('');
    expect(wrapper.emitted('update:modelValue').at(-1)[0].confirmed).toBeNull();
  });

  it('emits integer zero and an explicit empty draft value without coercing strings', async () => {
    const wrapper = mountFields(answers);
    await wrapper.get('[data-acw-answer="count"]').setValue('0');
    expect(wrapper.emitted('update:modelValue').at(-1)[0].count).toBe(0);
    await wrapper.get('[data-acw-answer="count"]').setValue('');
    expect(wrapper.emitted('update:modelValue').at(-1)[0].count).toBeNull();
  });

  it('allows a cleared selection to remain an incomplete typed draft', async () => {
    const wrapper = mountFields(answers);
    await wrapper.get('[data-acw-answer="result"]').setValue('');
    expect(wrapper.emitted('update:modelValue').at(-1)[0].result).toBeNull();
  });

  it('renders private text as text and never injects a stored HTML fragment', () => {
    answers.detail = '<img src=x onerror=alert(1)>';
    const wrapper = mountFields(answers);
    expect(wrapper.get('textarea').element.value).toBe(answers.detail);
    expect(wrapper.find('img').exists()).toBe(false);
  });

  it('does not overwrite answers or silently mark a different version complete', async () => {
    const wrapper = mountFields(answers);
    const next = {
      fields: [
        {
          key: 'next',
          label: 'SYNTHETIC revised field',
          type: 'text',
          required: true,
        },
      ],
    };
    await wrapper.setProps({ definition: next });
    expect(wrapper.get('textarea').element.value).toBe('');
    expect(wrapper.emitted('ready').at(-1)).toEqual([false]);
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    expect(answers.detail).toBe('SYNTHETIC text');
  });

  it('blocks edits while the owner is saving or reviewing an uncertain request', async () => {
    const wrapper = mountFields(answers, { disabled: true });
    await wrapper.get('textarea').setValue('SYNTHETIC blocked edit');
    expect(wrapper.get('fieldset').attributes('disabled')).toBeDefined();
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    expect(answers.detail).toBe('SYNTHETIC text');
  });

  it('fails closed on invalid definitions without exposing or discarding the draft', () => {
    const wrapper = mountFields(answers, { definition: { fields: [] } });
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'ACW_FORMS.INVALID_DEFINITION'
    );
    expect(wrapper.findAll('textarea,input,select')).toHaveLength(0);
    expect(wrapper.emitted('ready').at(-1)).toEqual([false]);
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    expect(wrapper.text()).not.toContain(answers.detail);
  });

  it('does not display inherited prototype values as an optional answer', () => {
    definition.fields = [
      {
        key: 'toString',
        label: 'SYNTHETIC own text',
        type: 'text',
        required: false,
      },
    ];
    const wrapper = mountFields();
    expect(wrapper.get('textarea').element.value).toBe('');
    expect(wrapper.emitted('ready').at(-1)).toEqual([true]);
  });
});
