import { describe, expect, it, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import RoutingDraftForm from './RoutingDraftForm.vue';
import IvrReferencePicker from './IvrReferencePicker.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
const initial = {
  version: 1,
  rule_key: 'SYNTHETIC rule',
  kind: 'ddd',
  source_value: '11',
  priority: 1,
  state: 'draft',
  target_unit_id: '3',
  target_queue_id: '4',
};
const render = fields =>
  mount(RoutingDraftForm, {
    props: { accountId: '1', modelValue: { ...initial }, ...fields },
    global: { stubs: { IvrReferencePicker: true } },
  });

describe('native routing draft fields', () => {
  it('labels a routing criterion independently of the operational unit kind', () => {
    const wrapper = render();
    expect(
      wrapper.get('[data-routing-kind]').element.closest('label').textContent
    ).toContain('JRC_CONTACT_CENTER.ROUTING_DRAFTS.KIND');
    expect(wrapper.text()).not.toContain('JRC_CONTACT_CENTER.ADMIN.KIND');
    wrapper.unmount();
  });

  it('uses authorized native reference pickers and resets a queue only when its unit is explicitly changed', () => {
    const wrapper = render();
    const [unit, queue] = wrapper.findAllComponents(IvrReferencePicker);
    expect(unit.props()).toMatchObject({
      accountId: '1',
      resource: 'units',
      modelValue: '3',
    });
    expect(queue.props()).toMatchObject({
      accountId: '1',
      resource: 'queues',
      unitId: '3',
      voiceOnly: false,
    });
    unit.vm.$emit('update:modelValue', '5');
    expect(wrapper.emitted('update:modelValue')[0][0]).toMatchObject({
      target_unit_id: '5',
      target_queue_id: null,
    });
    expect(wrapper.props('modelValue')).toEqual(initial);
    wrapper.unmount();
  });

  it('preserves the queue-only stored target while showing its authorized native unit context', () => {
    const wrapper = render({
      modelValue: { ...initial, target_unit_id: null },
      referenceUnit: '3',
    });
    const [unit, queue] = wrapper.findAllComponents(IvrReferencePicker);
    expect(unit.props('modelValue')).toBe('3');
    expect(queue.props('unitId')).toBe('3');
    expect(wrapper.props('modelValue').target_unit_id).toBeNull();
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    wrapper.unmount();
  });

  it('does not offer provider publication and keeps a historical published value read-only', () => {
    const wrapper = render({
      disabled: true,
      modelValue: { ...initial, state: 'published' },
    });
    expect(wrapper.get('fieldset').element.disabled).toBe(true);
    expect(wrapper.get('select[data-routing-state]').element.disabled).toBe(
      true
    );
    expect(wrapper.get('option[value="published"]').text()).toBe(
      'JRC_CONTACT_CENTER.ROUTING_DRAFTS.PUBLISHED_HISTORY'
    );
    expect(wrapper.find('button[data-publish]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('changes a queue-only legacy destination to its visible unit only after the user explicitly clears the queue', () => {
    const wrapper = render({
      modelValue: { ...initial, target_unit_id: null },
      referenceUnit: '3',
    });
    const queue = wrapper.findAllComponents(IvrReferencePicker)[1];
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    queue.vm.$emit('update:modelValue', '');
    expect(wrapper.emitted('update:modelValue')[0][0]).toMatchObject({
      target_unit_id: '3',
      target_queue_id: null,
    });
    expect(wrapper.props('modelValue').target_unit_id).toBeNull();
    wrapper.unmount();
  });
});
