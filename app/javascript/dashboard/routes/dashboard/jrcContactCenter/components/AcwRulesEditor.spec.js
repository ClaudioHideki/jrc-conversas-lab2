import { describe, expect, it, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import AcwRulesEditor from './AcwRulesEditor.vue';
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
const rule = {
  id: 'a',
  reason_code: 'order',
  scope: 'general',
  scope_id: null,
  active: true,
  limit_seconds: 120,
};
const mountEditor = (rules = [rule], extra = {}) =>
  mount(AcwRulesEditor, {
    props: { accountId: '1', modelValue: rules, ...extra },
    global: { stubs: { AcwRuleTarget: true } },
  });
describe('native scoped voice ACW editor', () => {
  it('adds only an explicitly inactive rule rather than activating a policy on creation', async () => {
    const wrapper = mountEditor([]);
    await wrapper.get('[data-add-acw-rule]').trigger('click');
    expect(wrapper.emitted('update:modelValue')[0][0][0]).toMatchObject({
      scope: 'general',
      scope_id: null,
      active: false,
      limit_seconds: null,
    });
    wrapper.unmount();
  });
  it('keeps IDs and existing data while editing the native reason code', async () => {
    const wrapper = mountEditor();
    await wrapper.get('[data-acw-rule-reason]').setValue('resolved');
    expect(wrapper.emitted('update:modelValue')[0][0]).toEqual([
      { ...rule, reason_code: 'resolved' },
    ]);
    expect(rule.reason_code).toBe('order');
    wrapper.unmount();
  });
  it('clears the old queue/team reference on a scope change', async () => {
    const wrapper = mountEditor([{ ...rule, scope: 'queue', scope_id: '12' }]);
    await wrapper.get('[data-acw-rule-scope]').setValue('team');
    expect(wrapper.emitted('update:modelValue')[0][0]).toEqual([
      { ...rule, scope: 'team', scope_id: null },
    ]);
    wrapper.unmount();
  });
  it('converts HH:MM to seconds without changing the exact rule identity', async () => {
    const wrapper = mountEditor();
    await wrapper.get('[data-acw-rule-time]').setValue('00:03');
    expect(wrapper.emitted('update:modelValue')[0][0]).toEqual([
      { ...rule, limit_seconds: 180 },
    ]);
    wrapper.unmount();
  });
  it.each(['00:00', '01:01', 'invalid'])(
    'does not silently invent a limit for %s',
    async value => {
      const wrapper = mountEditor();
      await wrapper.get('[data-acw-rule-time]').setValue(value);
      expect(
        wrapper.emitted('update:modelValue')[0][0][0].limit_seconds
      ).toBeNull();
      wrapper.unmount();
    }
  );
  it('preserves a legacy exact second value instead of rounding it to a minute on open', () => {
    const wrapper = mountEditor([{ ...rule, limit_seconds: 75 }]);
    expect(wrapper.get('[data-acw-rule-time]').element.value).toBe('');
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.ACW_RULES.EXACT_SECONDS'
    );
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    wrapper.unmount();
  });
  it('removes only the explicitly selected rule', async () => {
    const wrapper = mountEditor([rule, { ...rule, id: 'b' }]);
    await wrapper.findAll('[data-remove-acw-rule]')[0].trigger('click');
    expect(wrapper.emitted('update:modelValue')[0][0]).toEqual([
      { ...rule, id: 'b' },
    ]);
    wrapper.unmount();
  });
  it('disables scoped editing with the native parent authority or saving state', () => {
    const wrapper = mountEditor([rule], { disabled: true });
    expect(wrapper.get('fieldset').element.disabled).toBe(true);
    expect(wrapper.get('[data-add-acw-rule]').element.disabled).toBe(true);
    wrapper.unmount();
  });
});
