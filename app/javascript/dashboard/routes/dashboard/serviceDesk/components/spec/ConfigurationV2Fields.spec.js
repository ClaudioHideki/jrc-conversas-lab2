import { describe, it, expect, beforeEach, vi } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import ConfigurationV2Fields from '../ConfigurationV2Fields.vue';
import MembershipAvailability from '../MembershipAvailability.vue';
import { operationalDefaults } from '../../helpers/v2Configuration';
const mocks = vi.hoisted(() => ({ portalOptions: vi.fn(), session: null }));
vi.mock('dashboard/api/serviceDeskConfiguration', () => ({ default: mocks }));
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => mocks.session,
}));
const context = {
  account_id: '1',
  units: [{ id: '2' }],
  capabilities: { configuration: { services: true } },
};
const payload = () => ({
  contract_version: 1,
  account_id: '1',
  unit_id: '2',
  inboxes: [{ id: '4', name: 'Actual widget', source: 'native_widget' }],
  execution_memberships: [{ id: '7', name: 'Actual member' }],
});
beforeEach(() => {
  mocks.portalOptions.mockReset().mockResolvedValue(payload());
  mocks.session = {
    state: reactive({
      status: 'ready',
      context: { ...context, available: true },
    }),
    resource: vi.fn(() => ({ status: 'empty', items: [], meta: null })),
    resetResource: vi.fn(),
    load: vi.fn(),
  };
});
describe('Operational settings use the existing audited administration flow', () => {
  it('keeps a new queue manual and edits distribution metadata without invoking publication', async () => {
    const wrapper = mount(ConfigurationV2Fields, {
      props: {
        resource: 'queues',
        unitId: '2',
        context,
        modelValue: operationalDefaults('queues'),
      },
    });
    expect(wrapper.find('select').element.value).toBe('manual');
    await wrapper.find('select').setValue('least_load');
    expect(wrapper.emitted('update:modelValue')[0][0].distribution_mode).toBe(
      'least_load'
    );
    expect(mocks.portalOptions).not.toHaveBeenCalled();
    expect(wrapper.get('[data-clock-automatic]').element.checked).toBe(false);
    expect(
      wrapper.get('[data-clock-automatic]').attributes('disabled')
    ).toBeDefined();
    expect(mocks.session.load).not.toHaveBeenCalled();
    wrapper.unmount();
  });
  it('requires a real configured widget and native executor before portal enablement while default stays OFF', async () => {
    const modelValue = {
      ...operationalDefaults('services'),
      active: true,
      default_priority_id: '3',
    };
    const wrapper = mount(ConfigurationV2Fields, {
      props: { resource: 'services', unitId: '2', context, modelValue },
      global: { stubs: { LookupSelect: true } },
    });
    await flushPromises();
    const toggle = () => wrapper.findAll('input[type="checkbox"]').at(-1);
    expect(toggle().element.checked).toBe(false);
    expect(toggle().attributes('disabled')).toBeDefined();
    await wrapper.setProps({
      modelValue: {
        ...modelValue,
        portal_inbox_id: '4',
        portal_execution_membership_id: '7',
      },
    });
    await flushPromises();
    expect(mocks.portalOptions.mock.calls.at(-1)[2]).toBe('4');
    expect(toggle().attributes('disabled')).toBeUndefined();
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    await toggle().setValue(true);
    expect(wrapper.emitted('update:modelValue').at(-1)[0].portal_enabled).toBe(
      true
    );
    wrapper.unmount();
  });
  it('removes real authority choices after a foreign unit response and keeps publication unavailable', async () => {
    const wrapper = mount(ConfigurationV2Fields, {
      props: {
        resource: 'services',
        unitId: '2',
        context,
        modelValue: {
          ...operationalDefaults('services'),
          active: true,
          default_priority_id: '3',
        },
      },
      global: { stubs: { LookupSelect: true } },
    });
    await flushPromises();
    expect(wrapper.text()).toContain('Actual widget');
    mocks.portalOptions.mockResolvedValue({ ...payload(), unit_id: '9' });
    await wrapper.setProps({
      modelValue: { ...operationalDefaults('services'), portal_inbox_id: '4' },
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain('Actual widget');
    expect(
      wrapper.findAll('input[type="checkbox"]').at(-1).attributes('disabled')
    ).toBeDefined();
    wrapper.unmount();
  });
  it('edits availability and actual capacity separately from granting or revoking a membership', async () => {
    const wrapper = mount(MembershipAvailability, {
      props: {
        modelValue: {
          active: true,
          availability: 'unavailable',
          capacity: null,
          skills: [],
        },
      },
    });
    await wrapper.find('select').setValue('available');
    const saved = wrapper.emitted('update:modelValue')[0][0];
    expect(saved).toEqual({
      active: true,
      availability: 'available',
      capacity: null,
      skills: [],
    });
    await wrapper.find('input[type="number"]').setValue('2');
    expect(wrapper.emitted('update:modelValue').at(-1)[0].capacity).toBe(2);
    wrapper.unmount();
  });
});
