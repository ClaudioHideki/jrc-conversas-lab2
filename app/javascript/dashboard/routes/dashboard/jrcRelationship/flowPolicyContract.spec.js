import { describe, it, expect, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import PlaybookFlowPolicyForm from './PlaybookFlowPolicyForm.vue';
import {
  isPlaybookFlowPolicy,
  reviewedFlowEffects,
  flowMutationEffects,
} from './playbookFlowPolicy';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
const policy = () => ({
  phase: 1,
  approved_phase: 0,
  pilot_company_ids: [],
  pilot_business_unit_ids: [],
  pilot_account_user_ids: [],
  allow_unassigned_business_unit: false,
  approval_required: true,
  approval_ttl_seconds: 600,
  hourly_limit: 10,
  max_steps: 100,
  allowed_effects: ['note'],
});

describe('Finite native Flow policy decoding', () => {
  it('retains native OFF defaults and rejects unknown or duplicated effects, keys, pilots and wrong types', () => {
    const value = policy();
    expect(isPlaybookFlowPolicy(value)).toBe(true);
    expect(
      isPlaybookFlowPolicy({
        ...value,
        allowed_effects: ['note', 'future_effect'],
      })
    ).toBe(false);
    expect(
      isPlaybookFlowPolicy({ ...value, allowed_effects: ['note', 'note'] })
    ).toBe(false);
    expect(isPlaybookFlowPolicy({ ...value, automatic_execution: true })).toBe(
      false
    );
    expect(
      isPlaybookFlowPolicy({ ...value, pilot_account_user_ids: [7, 7] })
    ).toBe(false);
    expect(isPlaybookFlowPolicy({ ...value, pilot_company_ids: [0] })).toBe(
      false
    );
    expect(isPlaybookFlowPolicy({ ...value, approved_phase: '3' })).toBe(false);
    expect(isPlaybookFlowPolicy({ ...value, approval_required: 'true' })).toBe(
      false
    );
    expect(isPlaybookFlowPolicy({ ...value, max_steps: 201 })).toBe(false);
    expect(value).toEqual(policy());
  });

  it.each(['media', 'webhook', 'move_deal', 'nico'])(
    'allows an explicit %s change only after both phase-three fields are approved',
    effect => {
      const original = policy();
      expect(flowMutationEffects).toContain(effect);
      expect(reviewedFlowEffects(original, effect, true)).toBeNull();
      expect(
        reviewedFlowEffects(
          { ...original, phase: 3, approved_phase: 2 },
          effect,
          true
        )
      ).toBeNull();
      const approved = {
        ...original,
        phase: 3,
        approved_phase: 3,
        pilot_company_ids: [31],
        pilot_account_user_ids: [7],
      };
      expect(reviewedFlowEffects(approved, effect, true)).toEqual([
        'note',
        effect,
      ]);
      expect(approved.allowed_effects).toEqual(['note']);
      expect(approved.pilot_company_ids).toEqual([31]);
      expect(
        reviewedFlowEffects(
          { ...approved, allowed_effects: ['note', effect] },
          effect,
          false
        )
      ).toEqual(['note']);
      expect(reviewedFlowEffects(approved, 'unknown', true)).toBeNull();
      expect(original).toEqual(policy());
    }
  );

  it('blocks an unknown server policy visibly without replacing it, and recovers only after a valid native policy is supplied', async () => {
    const unknown = { ...policy(), allowed_effects: ['note', 'future_effect'] };
    const wrapper = mount(PlaybookFlowPolicyForm, {
      props: { modelValue: unknown },
    });
    expect(wrapper.find('fieldset').element.disabled).toBe(true);
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(wrapper.emitted('validity')).toEqual([[false]]);
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    expect(unknown.allowed_effects).toEqual(['note', 'future_effect']);
    await wrapper.setProps({
      modelValue: { ...policy(), allowed_effects: null },
    });
    expect(wrapper.find('fieldset').element.disabled).toBe(true);
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    await wrapper.setProps({ modelValue: policy() });
    expect(wrapper.find('fieldset').element.disabled).toBe(false);
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(wrapper.emitted('validity')).toEqual([[false], [true]]);
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    wrapper.unmount();
  });
});
