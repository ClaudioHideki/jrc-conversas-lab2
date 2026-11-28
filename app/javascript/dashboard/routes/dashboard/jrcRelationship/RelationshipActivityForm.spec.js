import { beforeEach, describe, expect, it, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import RelationshipActivityForm from './RelationshipActivityForm.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
beforeEach(() => vi.clearAllMocks());

describe('native reusable Relationship activity fields', () => {
  it('keeps the native title and optional deadline model and explicit submit contract', async () => {
    const wrapper = mount(RelationshipActivityForm);
    const title = wrapper.get('[data-native-relationship-activity-title]');
    const due = wrapper.get('[data-native-relationship-activity-deadline]');
    expect(title.attributes('required')).toBeDefined();
    expect(title.attributes('maxlength')).toBeUndefined();
    expect(due.attributes('required')).toBeUndefined();
    await title.setValue('SYNTHETIC native Relationship activity');
    await due.setValue('2026-11-30T10:00');
    await wrapper.get('form').trigger('submit');
    expect(wrapper.emitted('update:title')).toEqual([
      ['SYNTHETIC native Relationship activity'],
    ]);
    expect(wrapper.emitted('update:dueAt')).toEqual([['2026-11-30T10:00']]);
    expect(wrapper.emitted('submit')).toHaveLength(1);
  });

  it('renders existing parent values without creating a private parallel draft', () => {
    const wrapper = mount(RelationshipActivityForm, {
      props: { title: 'SYNTHETIC existing value', dueAt: '2026-11-30T12:30' },
    });
    expect(
      wrapper.get('[data-native-relationship-activity-title]').element.value
    ).toBe('SYNTHETIC existing value');
    expect(
      wrapper.get('[data-native-relationship-activity-deadline]').element.value
    ).toBe('2026-11-30T12:30');
    expect(wrapper.emitted('submit')).toBeUndefined();
  });

  it('can require an explicit deadline and bounded title for the recording intake without changing legacy defaults', () => {
    const wrapper = mount(RelationshipActivityForm, {
      props: { deadlineRequired: true, titleMaxLength: 250 },
    });
    expect(
      wrapper
        .get('[data-native-relationship-activity-title]')
        .attributes('maxlength')
    ).toBe('250');
    expect(
      wrapper
        .get('[data-native-relationship-activity-deadline]')
        .attributes('required')
    ).toBeDefined();
    expect(wrapper.emitted('submit')).toBeUndefined();
  });

  it('blocks another submit and field edits during an owned native save', async () => {
    const wrapper = mount(RelationshipActivityForm, {
      props: { disabled: true },
    });
    expect(
      wrapper.get('[data-native-relationship-activity-title]').element.disabled
    ).toBe(true);
    expect(
      wrapper.get('[data-native-relationship-activity-deadline]').element
        .disabled
    ).toBe(true);
    expect(wrapper.get('button[type="submit"]').element.disabled).toBe(true);
    await wrapper.get('form').trigger('submit');
    expect(wrapper.emitted('submit')).toBeUndefined();
  });
});
