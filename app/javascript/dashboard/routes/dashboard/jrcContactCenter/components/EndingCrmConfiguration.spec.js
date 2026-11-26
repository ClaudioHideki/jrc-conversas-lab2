import { describe, expect, it, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import EndingCrmConfiguration from './EndingCrmConfiguration.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
const options = {
  configuration_available: true,
  activity_types: ['call', 'meeting'],
};
const create = (props = {}) =>
  mount(EndingCrmConfiguration, { props: { options, ...props } });

// Component validation only: native API and Chrome remain separate mandatory proof.
describe('native CRM rule parameters', () => {
  it('requires explicit operation selection and prospective review before applying a lead action', async () => {
    const wrapper = create();
    expect(wrapper.get('[data-ending-crm-apply]').element.disabled).toBe(true);
    await wrapper.get('[data-ending-crm-operation]').setValue('contact_lead');
    expect(wrapper.get('[data-ending-crm-apply]').element.disabled).toBe(true);
    await wrapper.get('[data-ending-crm-reviewed]').setValue(true);
    await wrapper.get('form').trigger('submit');
    expect(wrapper.emitted('save')).toEqual([[{}]]);
    expect(wrapper.text()).toContain('CRM_CONFIGURATION.AUTHORITY');
    wrapper.unmount();
  });

  it('requires a native activity type and valid title without adding caller identity or company fields', async () => {
    const wrapper = create();
    await wrapper
      .get('[data-ending-crm-operation]')
      .setValue('create_activity');
    await wrapper.get('[data-ending-crm-reviewed]').setValue(true);
    await wrapper.get('form').trigger('submit');
    expect(wrapper.emitted('save')).toBeUndefined();
    await wrapper.get('[data-ending-crm-activity-type]').setValue('call');
    await wrapper
      .get('[data-ending-crm-title]')
      .setValue('SYNTHETIC reviewed activity');
    await wrapper
      .get('[data-ending-crm-description]')
      .setValue('SYNTHETIC operational result');
    expect(wrapper.get('[data-ending-crm-reviewed]').element.checked).toBe(
      false
    );
    await wrapper.get('[data-ending-crm-reviewed]').setValue(true);
    await wrapper.get('form').trigger('submit');
    expect(wrapper.emitted('save')).toEqual([
      [
        {
          operation: 'create_activity',
          parameters: {
            activity_type: 'call',
            title: 'SYNTHETIC reviewed activity',
            description: 'SYNTHETIC operational result',
          },
        },
      ],
    ]);
    wrapper.unmount();
  });

  it('retains the stored parameters but requires a fresh review before applying an existing activity', async () => {
    const value = {
      operation: 'create_activity',
      parameters: {
        activity_type: 'meeting',
        title: 'SYNTHETIC saved',
        description: 'SYNTHETIC saved notes',
      },
    };
    const wrapper = create({ value });
    expect(wrapper.get('[data-ending-crm-title]').element.value).toBe(
      'SYNTHETIC saved'
    );
    expect(wrapper.get('[data-ending-crm-apply]').element.disabled).toBe(true);
    await wrapper.get('[data-ending-crm-title]').setValue('SYNTHETIC changed');
    expect(value.parameters.title).toBe('SYNTHETIC saved');
    expect(wrapper.emitted('save')).toBeUndefined();
    wrapper.unmount();
  });

  it('revokes apply when current native CRM options become unavailable, without clearing the local draft silently', async () => {
    const wrapper = create({
      value: {
        operation: 'create_activity',
        parameters: { activity_type: 'call', title: 'SYNTHETIC retained' },
      },
    });
    await wrapper.get('[data-ending-crm-reviewed]').setValue(true);
    await wrapper.setProps({
      options: { configuration_available: false, activity_types: [] },
    });
    await wrapper.get('form').trigger('submit');
    expect(wrapper.emitted('save')).toBeUndefined();
    expect(wrapper.get('[data-ending-crm-title]').element.value).toBe(
      'SYNTHETIC retained'
    );
    wrapper.unmount();
  });

  it('does not apply while the parent is saving even after a valid explicit review', async () => {
    const wrapper = create();
    await wrapper.get('[data-ending-crm-operation]').setValue('contact_lead');
    await wrapper.get('[data-ending-crm-reviewed]').setValue(true);
    await wrapper.setProps({ disabled: true });
    await wrapper.get('form').trigger('submit');
    expect(wrapper.emitted('save')).toBeUndefined();
    expect(wrapper.get('[data-ending-crm-apply]').element.disabled).toBe(true);
    wrapper.unmount();
  });

  it('offers removal only for an existing destination and never saves on cancel', async () => {
    const wrapper = create({ value: {} });
    const buttons = wrapper.findAll('button');
    await buttons[1].trigger('click');
    expect(wrapper.emitted('cancel')).toEqual([[]]);
    expect(wrapper.emitted('save')).toBeUndefined();
    await buttons[2].trigger('click');
    expect(wrapper.emitted('remove')).toEqual([[]]);
    expect(wrapper.emitted('save')).toBeUndefined();
    wrapper.unmount();
  });
});
