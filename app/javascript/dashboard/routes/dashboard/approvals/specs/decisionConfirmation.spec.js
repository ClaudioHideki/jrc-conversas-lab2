import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { expect, it, vi } from 'vitest';
import locale from 'dashboard/i18n/locale/en/jrcApprovals.json';
import Component from '../ApprovalDecisionDialog.vue';
import RequestDetail from '../RequestDetail.vue';
const Dialog = {
  props: ['disableConfirmButton', 'dismissible', 'isLoading'],
  emits: ['confirm', 'close'],
  setup(_, { expose, emit }) {
    expose({ open: vi.fn(), close: () => emit('close') });
  },
  template:
    '<section role="dialog"><slot /><button data-confirm :disabled="disableConfirmButton || isLoading" @click="$emit(\'confirm\')">Confirm</button><button data-cancel :disabled="!dismissible" @click="$emit(\'close\')">Cancel</button></section>',
};
const Button = {
  props: ['label', 'disabled'],
  template: '<button :disabled="disabled">{{ label }}</button>',
};
const record = {
  id: 8,
  state: 'pending',
  lock_version: 4,
  policy_name: 'SYNTHETIC approval',
  stages: [{ code: 'internal_review', quorum: 1 }],
  allowed_decisions: [
    {
      step_code: 'internal_review',
      choices: [
        {
          delegation_id: 99,
          principal_name: 'Scoped principal',
          actions: ['approved'],
        },
      ],
    },
  ],
};
const choice = {
  step_code: 'internal_review',
  delegation_id: 99,
  principal_name: 'Scoped principal',
  decision: 'approved',
};
const options = props => ({
  props,
  global: {
    plugins: [
      createI18n({ legacy: false, locale: 'en', messages: { en: locale } }),
    ],
    stubs: { Dialog, Button },
  },
});
const render = props =>
  mount(
    Component,
    options({
      request: record,
      choice,
      reason: '  Explicit review  ',
      ...props,
    })
  );
it('requires explicit confirmation, pins the native version and prevents duplicate clicks without changing the choice', async () => {
  const wrapper = render();
  await flushPromises();
  expect(wrapper.emitted('confirm')).toBeUndefined();
  expect(wrapper.text()).toContain('On behalf of Scoped principal');
  expect(wrapper.text()).not.toContain('internal_review');
  await wrapper.get('[data-confirm]').trigger('click');
  wrapper.getComponent(Dialog).vm.$emit('confirm');
  expect(wrapper.emitted('confirm')).toHaveLength(1);
  expect(wrapper.emitted('confirm')[0][0]).toEqual({
    step_code: 'internal_review',
    decision: 'approved',
    delegation_id: 99,
    reason: 'Explicit review',
    expected_version: 4,
  });
  wrapper.unmount();
});
it('keeps busy, empty-reason or outdated requests unable to submit even if a confirm event is forced', async () => {
  const wrapper = render({ busy: true });
  await flushPromises();
  wrapper.getComponent(Dialog).vm.$emit('confirm');
  expect(wrapper.emitted('confirm')).toBeUndefined();
  await wrapper.setProps({ busy: false, reason: ' ' });
  wrapper.getComponent(Dialog).vm.$emit('confirm');
  expect(wrapper.emitted('confirm')).toBeUndefined();
  await wrapper.setProps({
    reason: 'New reason',
    request: { ...record, lock_version: 5 },
  });
  wrapper.getComponent(Dialog).vm.$emit('confirm');
  expect(wrapper.emitted('confirm')).toBeUndefined();
  wrapper.unmount();
});
it('shows a server error inside the popup and permits a deliberate retry after a fast failed response', async () => {
  const wrapper = render();
  await flushPromises();
  await wrapper.get('[data-confirm]').trigger('click');
  await wrapper.setProps({
    error: 'Review denied',
    errorState: { status: 422 },
  });
  expect(wrapper.get('[role="alert"]').text()).toBe('Review denied');
  expect(wrapper.get('[data-confirm]').element.disabled).toBe(false);
  await wrapper.get('[data-confirm]').trigger('click');
  expect(wrapper.emitted('confirm')).toHaveLength(2);
  wrapper.unmount();
});
it('cancels without producing a decision', async () => {
  const wrapper = render();
  await flushPromises();
  await wrapper.get('[data-cancel]').trigger('click');
  expect(wrapper.emitted('close')).toHaveLength(1);
  expect(wrapper.emitted('confirm')).toBeUndefined();
  wrapper.unmount();
});
it('invalidates a prepared confirmation when the request version, state or allowed choices change', async () => {
  const wrapper = mount(RequestDetail, options({ request: record }));
  await wrapper.get('textarea').setValue('Explicit reviewed reason');
  await wrapper
    .findAll('button')
    .find(button => button.text().startsWith('Approve'))
    .trigger('click');
  await flushPromises();
  expect(wrapper.findComponent(Component).exists()).toBe(true);
  await wrapper.setProps({ request: { ...record, lock_version: 5 } });
  await flushPromises();
  expect(wrapper.findComponent(Component).exists()).toBe(false);
  expect(wrapper.emitted('decide')).toBeUndefined();
  wrapper.unmount();
});
