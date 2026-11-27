import { afterEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import LinkedContactMaster from './LinkedContactMaster.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock(
  'dashboard/routes/dashboard/jrcCustomers/components/ContactDetailsDialog.vue',
  () => ({
    default: {
      props: {
        contactId: { type: [String, Number], required: true },
        openFullPageInNewTab: { type: Boolean, default: false },
        initialTab: { type: String, default: 'overview' },
      },
      emits: ['close', 'updated'],
      template:
        '<div data-native-master :data-independent-full-page="openFullPageInNewTab" :data-initial-tab="initialTab">{{ contactId }}<button data-close @click="$emit(\'close\')" /><button data-updated @click="$emit(\'updated\')" /></div>',
    },
  })
);
const customer = () => ({
  status: 'identified',
  ambiguous: false,
  contacts: [{ id: '2', name: 'SYNTHETIC contact' }],
  directory: { contact_id: '2' },
});
const render = (props = {}) =>
  mount(LinkedContactMaster, {
    props: {
      accountId: '1',
      call: { id: 7, contact_id: 2 },
      customer: customer(),
      enabled: true,
      ...props,
    },
  });
enableAutoUnmount(afterEach);

describe('explicit native master entry from a call', () => {
  it('does not turn a unique telephone candidate into a linked record', () => {
    const wrapper = render({ call: { id: 7 } });
    expect(wrapper.find('[data-open-linked-master]').exists()).toBe(false);
  });
  it('does not offer a master entry without the server directory authorization', () => {
    const wrapper = render({ customer: { ...customer(), directory: null } });
    expect(wrapper.find('[data-open-linked-master]').exists()).toBe(false);
  });
  it('rejects a different contact identifier returned in the directory entry', () => {
    const wrapper = render({
      customer: { ...customer(), directory: { contact_id: '3' } },
    });
    expect(wrapper.find('[data-open-linked-master]').exists()).toBe(false);
  });
  it('does not select the first ambiguous contact', () => {
    const wrapper = render({
      customer: {
        ...customer(),
        ambiguous: true,
        contacts: [{ id: 2 }, { id: 3 }],
      },
    });
    expect(wrapper.find('[data-open-linked-master]').exists()).toBe(false);
  });
  it('opens and closes the existing native dialog only after an explicit click', async () => {
    const wrapper = render();
    expect(wrapper.find('[data-native-master]').exists()).toBe(false);
    await wrapper.get('[data-open-linked-master]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-native-master]').text()).toBe('2');
    expect(
      wrapper
        .get('[data-native-master]')
        .attributes('data-independent-full-page')
    ).toBe('true');
    await wrapper.get('[data-close]').trigger('click');
    expect(wrapper.emitted('closed')).toHaveLength(1);
    expect(wrapper.find('[data-native-master]').exists()).toBe(false);
  });
  it('closes the dialog when the call or account changes', async () => {
    const wrapper = render();
    await wrapper.get('[data-open-linked-master]').trigger('click');
    await flushPromises();
    await wrapper.setProps({ accountId: '9', call: { id: 8 } });
    expect(wrapper.emitted('closed')).toBeUndefined();
    expect(wrapper.find('[data-native-master]').exists()).toBe(false);
    expect(wrapper.find('[data-open-linked-master]').exists()).toBe(false);
  });
  it('clears an open native dialog after operate authority is removed', async () => {
    const wrapper = render();
    await wrapper.get('[data-open-linked-master]').trigger('click');
    await flushPromises();
    await wrapper.setProps({ enabled: false });
    expect(wrapper.find('[data-native-master]').exists()).toBe(false);
    expect(wrapper.find('[data-open-linked-master]').exists()).toBe(false);
  });
  it('forwards a confirmed native update without sending or creating an attendance action', async () => {
    const wrapper = render();
    await wrapper.get('[data-open-linked-master]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-updated]').trigger('click');
    expect(wrapper.emitted('updated')).toHaveLength(1);
    expect(wrapper.emitted('created')).toBeUndefined();
  });

  it('opens the exact native history section only after an explicit scoped history click', async () => {
    const wrapper = render({ showHistory: true });
    expect(wrapper.find('[data-native-master]').exists()).toBe(false);
    await wrapper.get('[data-open-linked-history]').trigger('click');
    await flushPromises();
    expect(
      wrapper.get('[data-native-master]').attributes('data-initial-tab')
    ).toBe('history');
    expect(wrapper.get('[data-native-master]').text()).toBe('2');
    await wrapper.setProps({ enabled: false });
    expect(wrapper.find('[data-open-linked-history]').exists()).toBe(false);
    expect(wrapper.find('[data-native-master]').exists()).toBe(false);
  });

  it('does not expose a history shortcut by default or without the native directory authorization', async () => {
    const wrapper = render();
    expect(wrapper.find('[data-open-linked-history]').exists()).toBe(false);
    await wrapper.setProps({
      showHistory: true,
      customer: { ...customer(), directory: null },
    });
    expect(wrapper.find('[data-open-linked-history]').exists()).toBe(false);
    expect(wrapper.find('[data-open-linked-master]').exists()).toBe(false);
  });
});
