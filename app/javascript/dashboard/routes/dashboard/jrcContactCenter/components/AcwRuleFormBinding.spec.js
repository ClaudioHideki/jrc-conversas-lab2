import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import AcwRuleFormBinding from './AcwRuleFormBinding.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { acwFormVersion: vi.fn() },
}));
vi.mock('./AcwFormLibrary.vue', () => ({
  default: {
    props: ['accountId'],
    emits: ['select', 'close'],
    template: '<section data-picker />',
  },
}));
enableAutoUnmount(afterEach);
const item = {
  id: '31',
  revision: 2,
  status: 'active',
  name: 'SYNTHETIC selected form',
  definition: {
    fields: [
      { key: 'required', label: 'Required', type: 'text', required: true },
      { key: 'optional', label: 'Optional', type: 'text', required: false },
    ],
  },
};
const binding = {
  rule_id: 'own-rule',
  form_id: '31',
  revision: 2,
  required_fields: ['required'],
};
const fixture = (props = {}) =>
  mount(AcwRuleFormBinding, {
    props: {
      accountId: '1',
      ruleId: 'own-rule',
      modelValue: binding,
      ...props,
    },
  });
beforeEach(() => {
  vi.clearAllMocks();
  API.acwFormVersion.mockResolvedValue({ data: { item } });
});

describe('Exact version binding inside the native ACW rule editor', () => {
  it('does not fetch every schema merely by opening the rule editor', () => {
    fixture();
    expect(API.acwFormVersion).not.toHaveBeenCalled();
  });
  it('reviews the exact frozen revision and allows additional required fields without removing schema-required fields', async () => {
    const wrapper = fixture();
    await wrapper.get('[data-review-rule-form]').trigger('click');
    await flushPromises();
    expect(API.acwFormVersion).toHaveBeenCalledWith('1', '31', 2);
    expect(
      wrapper.get('[data-required-form-field="required"]').element.disabled
    ).toBe(true);
    await wrapper.get('[data-required-form-field="optional"]').setValue(true);
    expect(wrapper.emitted('update:modelValue')[0]).toEqual([
      { ...binding, required_fields: ['optional', 'required'] },
    ]);
  });
  it('clears stale schema and ignores a late response after an account change', async () => {
    let resolve;
    API.acwFormVersion.mockReturnValueOnce(
      new Promise(done => {
        resolve = done;
      })
    );
    const wrapper = fixture();
    await wrapper.get('[data-review-rule-form]').trigger('click');
    await wrapper.setProps({ accountId: '2' });
    resolve({ data: { item } });
    await flushPromises();
    expect(wrapper.find('[data-required-form-field]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain(item.name);
  });
  it('requires a successful exact-version read rather than accepting a different version', async () => {
    API.acwFormVersion.mockResolvedValueOnce({
      data: { item: { ...item, revision: 3 } },
    });
    const wrapper = fixture();
    await wrapper.get('[data-review-rule-form]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(wrapper.find('[data-required-form-field]').exists()).toBe(false);
  });
  it('closes the reused picker and removes its schema when permission becomes read-only', async () => {
    const wrapper = fixture();
    await wrapper.get('[data-pick-rule-form]').trigger('click');
    expect(wrapper.find('[data-picker]').exists()).toBe(true);
    await wrapper.setProps({ disabled: true });
    expect(wrapper.find('[data-picker]').exists()).toBe(false);
    expect(wrapper.get('[data-clear-rule-form]').element.disabled).toBe(true);
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  });
  it('unlinks only after an explicit action without mutating the incoming frozen pin', async () => {
    const wrapper = fixture();
    await wrapper.get('[data-clear-rule-form]').trigger('click');
    expect(wrapper.emitted('update:modelValue')[0]).toEqual([null]);
    expect(binding.form_id).toBe('31');
    expect(API.acwFormVersion).not.toHaveBeenCalled();
  });
});
