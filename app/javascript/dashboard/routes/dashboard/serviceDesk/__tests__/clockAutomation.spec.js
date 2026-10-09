import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import {
  escalationPolicy,
  operationalDefaults,
} from '../helpers/v2Configuration';
import { SERVICE_DESK_ROUTES } from '../routeDefinitions';
const holder = vi.hoisted(() => ({ session: null }));
vi.mock('../composables/useServiceDesk', () => ({
  useServiceDesk: () => holder.session,
}));
import ClockAutomationFields from '../components/ClockAutomationFields.vue';
import AutomationsView from '../views/AutomationsView.vue';
const policy = overrides => ({
  enabled: true,
  thresholds: [{ percent: 70, queue_id: null, team_id: null }],
  ...overrides,
});
const LookupSelect = {
  name: 'LookupSelect',
  props: ['modelValue', 'unitId', 'resource', 'disabled'],
  emits: ['update:modelValue'],
  template:
    '<button data-executor :disabled="disabled" @click="$emit(\'update:modelValue\', \'21\')">Explicit operator</button>',
};
const Button = { props: ['label'], template: '<button>{{ label }}</button>' };
const i18n = () =>
  createI18n({
    legacy: false,
    locale: 'en',
    missingWarn: false,
    fallbackWarn: false,
  });
let wrapper;
beforeEach(() => {
  holder.session = {
    state: reactive({
      status: 'ready',
      context: {
        available: true,
        capabilities: {
          automations: { index: true },
          lifecycle_policies: { publish: true },
          configuration: { queues: true },
          notifications: { manage: true },
        },
      },
    }),
  };
});
afterEach(() => {
  wrapper?.unmount();
  wrapper = null;
});
const renderFields = value => {
  wrapper = mount(ClockAutomationFields, {
    props: { modelValue: value, unitId: '10' },
    global: { plugins: [i18n()], stubs: { LookupSelect } },
  });
  return wrapper;
};
const renderAutomations = () => {
  wrapper = mount(AutomationsView, {
    global: {
      plugins: [i18n()],
      stubs: {
        Button,
        LifecyclePolicyEditor: { template: '<div data-lifecycle-native />' },
        ConfigurationManager: {
          props: ['resource'],
          template: '<div data-ola-native :data-resource="resource" />',
        },
        NotificationPolicyEditor: {
          template: '<div data-notification-native />',
        },
      },
    },
  });
  return wrapper;
};

describe('finite native clock automation contract', () => {
  it('preserves the legacy manual definition and empty policy without automatically enabling anything', () => {
    expect(escalationPolicy({})).toEqual({});
    expect(escalationPolicy(policy())).toEqual(policy());
    expect(operationalDefaults('queues').ola_escalation_policy).toEqual({});
  });
  it('preserves canonical BIGINT executor and queue identities without numeric precision loss', () => {
    const input = policy({
      automatic: true,
      execution_account_user_id: '9223372036854775807',
      thresholds: [{ percent: 70, queue_id: '12', team_id: null }],
    });
    expect(escalationPolicy(input)).toEqual(input);
  });
  it.each([
    { automatic: true },
    { automatic: true, enabled: false, execution_account_user_id: '21' },
    { automatic: 'true', execution_account_user_id: '21' },
    { automatic: true, execution_account_user_id: '01' },
    { automatic: true, execution_account_user_id: '9223372036854775808' },
    {
      automatic: true,
      execution_account_user_id: Number.MAX_SAFE_INTEGER + 1,
    },
    { headers: {} },
  ])('rejects unsupported or incomplete automation input %j', input => {
    expect(() => escalationPolicy(policy(input))).toThrow(TypeError);
  });
  it('keeps an explicitly disabled policy and executor selection without inferring an automatic grant', () => {
    expect(
      escalationPolicy(
        policy({ automatic: false, execution_account_user_id: null })
      )
    ).toEqual(policy({ automatic: false, execution_account_user_id: null }));
  });
});

describe('native clock controls and automation view', () => {
  it('starts OFF and requires explicit executor before automatic activation', async () => {
    renderFields(policy());
    expect(wrapper.get('[data-clock-automatic]').element.checked).toBe(false);
    expect(
      wrapper.get('[data-clock-automatic]').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.findComponent(LookupSelect).props()).toMatchObject({
      resource: 'assignees',
      unitId: '10',
      modelValue: '',
    });
    await wrapper.get('[data-executor]').trigger('click');
    const chosen = wrapper.emitted('update:modelValue')[0][0];
    expect(chosen).toEqual(
      policy({ automatic: false, execution_account_user_id: '21' })
    );
    await wrapper.setProps({ modelValue: chosen });
    await wrapper.get('[data-clock-automatic]').setValue(true);
    expect(wrapper.emitted('update:modelValue')[1][0]).toEqual(
      policy({ automatic: true, execution_account_user_id: '21' })
    );
  });
  it('changing the executor invalidates the previous automatic selection rather than borrowing grants', async () => {
    renderFields(policy({ automatic: true, execution_account_user_id: '20' }));
    await wrapper.get('[data-executor]').trigger('click');
    expect(wrapper.emitted('update:modelValue')[0][0]).toEqual(
      policy({ automatic: false, execution_account_user_id: '21' })
    );
  });
  it('blocks activation without unit, without thresholds or while the editor is disabled', async () => {
    renderFields(policy({ automatic: false, execution_account_user_id: '21' }));
    await wrapper.setProps({ unitId: '' });
    expect(
      wrapper.get('[data-clock-automatic]').attributes('disabled')
    ).toBeDefined();
    await wrapper.setProps({ unitId: '10', modelValue: {} });
    expect(
      wrapper.get('[data-clock-automatic]').attributes('disabled')
    ).toBeDefined();
    await wrapper.setProps({
      modelValue: policy({ automatic: false, execution_account_user_id: '21' }),
      disabled: true,
    });
    await wrapper
      .findComponent(LookupSelect)
      .vm.$emit('update:modelValue', '22');
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  });
  it('reuses the native policy, queue and notification editors only under affirmative backend grants', async () => {
    renderAutomations();
    expect(wrapper.find('[data-lifecycle-native]').exists()).toBe(true);
    await wrapper.findAll('button')[1].trigger('click');
    expect(wrapper.get('[data-ola-native]').attributes('data-resource')).toBe(
      'queues'
    );
    await wrapper.findAll('button')[2].trigger('click');
    expect(wrapper.find('[data-notification-native]').exists()).toBe(true);
    holder.session.state.context.capabilities.notifications.manage = false;
    await flushPromises();
    expect(wrapper.find('[data-notification-native]').exists()).toBe(false);
    expect(wrapper.find('[data-lifecycle-native]').exists()).toBe(true);
  });
  it('clears automation controls after current account authorization is revoked', async () => {
    renderAutomations();
    holder.session.state.context = null;
    holder.session.state.status = 'denied';
    await flushPromises();
    expect(wrapper.text()).toBe('');
  });
  it('registers actual native views for automations, contracts and surveys instead of planned placeholders', () => {
    expect(
      SERVICE_DESK_ROUTES.find(row => row.key === 'automations').page
    ).toBe('automations');
    expect(
      SERVICE_DESK_ROUTES.find(row => row.key === 'contracts')
    ).toMatchObject({ page: 'catalog', resource: 'contracts' });
    expect(
      SERVICE_DESK_ROUTES.find(row => row.key === 'surveys')
    ).toMatchObject({ page: 'nativeSurveys', resource: 'surveys' });
  });
});
