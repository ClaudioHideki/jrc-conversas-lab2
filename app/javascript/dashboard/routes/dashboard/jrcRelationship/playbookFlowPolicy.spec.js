import { describe, it, expect, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import PlaybookFlowPolicyForm from './PlaybookFlowPolicyForm.vue';
import { playbookFlowLabels } from './playbookFlowLabels';
import translations from 'dashboard/i18n/locale/en/relationship.json';

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

describe('Native reviewed Flow policy form', () => {
  it.each(['media', 'webhook', 'move_deal', 'nico'])(
    'requires explicit phase-three approval before enabling %s',
    async effect => {
      const wrapper = mount(PlaybookFlowPolicyForm, {
        props: { modelValue: policy() },
      });
      expect(
        wrapper.get(`[data-testid="flow-effect-${effect}"]`).element.disabled
      ).toBe(true);
      expect(
        wrapper.get(`[data-testid="flow-effect-${effect}"]`).element.checked
      ).toBe(false);
      expect(wrapper.emitted('update:modelValue')).toBeUndefined();
      const approved = { ...policy(), phase: 3, approved_phase: 3 };
      await wrapper.setProps({ modelValue: approved });
      await wrapper.get(`[data-testid="flow-effect-${effect}"]`).setValue(true);
      expect(wrapper.emitted('update:modelValue')[0][0]).toEqual({
        ...approved,
        allowed_effects: ['note', effect],
      });
      expect(approved.allowed_effects).toEqual(['note']);
      wrapper.unmount();
    }
  );
  it('keeps mutation effects OFF until phase three is explicitly approved and changes only the chosen effect', async () => {
    const wrapper = mount(PlaybookFlowPolicyForm, {
      props: { modelValue: policy() },
    });
    expect(
      wrapper.get('[data-testid="flow-effect-status"]').element.disabled
    ).toBe(true);
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    const approved = { ...policy(), phase: 3, approved_phase: 3 };
    await wrapper.setProps({ modelValue: approved });
    await wrapper.get('[data-testid="flow-effect-status"]').setValue(true);
    expect(wrapper.emitted('update:modelValue')[0][0]).toEqual({
      ...approved,
      allowed_effects: ['note', 'status'],
    });
    expect(approved.allowed_effects).toEqual(['note']);
    wrapper.unmount();
  });
  it('uses existing translated keys for finite block reasons and a clear fallback for an unknown code', () => {
    const translate = key => {
      const value = key
        .split('.')
        .reduce((node, field) => node?.[field], translations);
      expect(typeof value).toBe('string');
      return value;
    };
    const label = playbookFlowLabels(translate);
    expect(label('playbook_flow_effects_disabled')).toBe(
      'Playbook Flow effects are OFF'
    );
    expect(
      label('native_relationship_delivery_guard_required:webhook')
    ).toContain('required playbook execution guard');
    expect(label('future-unknown-code')).toContain('Execution blocked');
    expect(label(null)).toBe('');
  });

  it('shows the exact backend policy without approving a phase, enabling effects or selecting pilots automatically', () => {
    const value = policy();
    const wrapper = mount(PlaybookFlowPolicyForm, {
      props: { modelValue: value },
    });
    expect(
      wrapper.get('[data-testid="flow-policy-approved_phase"]').element.value
    ).toBe('0');
    expect(
      wrapper.get('[data-testid="flow-policy-pilot_company_ids"]').element.value
    ).toBe('');
    expect(
      wrapper.get('[data-testid="flow-policy-approval_required"]').element
        .checked
    ).toBe(true);
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    expect(value).toEqual(policy());
    wrapper.unmount();
  });

  it('emits typed explicit pilot IDs while preserving all other policy fields', async () => {
    const value = policy();
    const wrapper = mount(PlaybookFlowPolicyForm, {
      props: { modelValue: value },
    });
    await wrapper
      .get('[data-testid="flow-policy-pilot_company_ids"]')
      .setValue('15, 29');
    expect(wrapper.emitted('update:modelValue')).toEqual([
      [{ ...value, pilot_company_ids: [15, 29] }],
    ]);
    expect(wrapper.emitted('validity')).toEqual([[true]]);
    expect(value.pilot_company_ids).toEqual([]);
    wrapper.unmount();
  });

  it('rejects duplicate or malformed pilot IDs and prevents a fractional execution budget from replacing the policy', async () => {
    const wrapper = mount(PlaybookFlowPolicyForm, {
      props: { modelValue: policy() },
    });
    await wrapper
      .get('[data-testid="flow-policy-pilot_company_ids"]')
      .setValue('15, 15');
    await wrapper
      .get('[data-testid="flow-policy-pilot_account_user_ids"]')
      .setValue('invalid');
    await wrapper
      .get('[data-testid="flow-policy-hourly_limit"]')
      .setValue('1.5');
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    expect(wrapper.emitted('validity')).toEqual([[false], [false], [false]]);
    expect(wrapper.get('[role="alert"]').text()).toBe(
      'RELATIONSHIP.FLOW_POLICY.INVALID'
    );
    wrapper.unmount();
  });
});
