import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { expect, it, vi } from 'vitest';
import locale from 'dashboard/i18n/locale/en/jrcApprovals.json';
import Component from '../AdjustmentDialog.vue';
import RequestDetail from '../RequestDetail.vue';
import { auditPresentation } from '../model';
const Dialog = {
  props: ['disableConfirmButton', 'dismissible', 'isLoading'],
  emits: ['confirm', 'close'],
  setup(_, { expose }) {
    expose({ open: vi.fn() });
  },
  template:
    '<section role="dialog"><slot /><button data-confirm :disabled="disableConfirmButton || isLoading" @click="$emit(\'confirm\')">Save</button><button data-cancel :disabled="!dismissible" @click="$emit(\'close\')">Cancel</button></section>',
};
const Button = {
  props: ['label', 'disabled'],
  template: '<button :disabled="disabled">{{ label }}</button>',
};
const record = {
  id: 8,
  state: 'pending',
  lock_version: 4,
  policy_name: 'Synthetic adjustment policy',
  stages: [{ code: 'private_review', quorum: 1 }],
  adjustment: { values: { discount_cents: 300 }, currency: 'BRL' },
  allowed_decisions: [
    {
      step_code: 'private_review',
      choices: [{ delegation_id: null, actions: ['approved', 'rejected'] }],
    },
  ],
};
const options = props => ({
  props,
  global: {
    plugins: [
      createI18n({ legacy: false, locale: 'en', messages: { en: locale } }),
    ],
    stubs: { Dialog, Button, ApprovalOriginLink: true },
  },
});
it('projects only the installed before/after discount from an adjustment audit', () => {
  const result = auditPresentation({
    id: 1,
    event_type: 'request_adjusted',
    data: {
      before: { discount_cents: 300, private_token: 'do-not-show' },
      after: { discount_cents: 100 },
      currency: 'BRL',
      reason: 'Synthetic',
    },
  });
  expect(result.adjustment).toEqual({
    before: 300,
    after: 100,
    currency: 'BRL',
  });
  expect(JSON.stringify(result)).not.toContain('do-not-show');
});
it('saves exact permitted cents with a mandatory reason, pinned version and no inferred decision', async () => {
  const wrapper = mount(Component, options({ request: record }));
  expect(wrapper.find('[data-confirm]').attributes('disabled')).toBeDefined();
  await wrapper.find('input').setValue('1,50');
  await wrapper.find('textarea').setValue('  Synthetic corrected discount  ');
  await wrapper.find('[data-confirm]').trigger('click');
  expect(wrapper.emitted('confirm')[0][0]).toEqual({
    changes: { discount_cents: 150 },
    mode: 'save',
    reason: 'Synthetic corrected discount',
    expected_version: 4,
  });
  await wrapper.find('[data-confirm]').trigger('click');
  expect(wrapper.emitted('confirm')).toHaveLength(1);
  expect(wrapper.text()).not.toContain('private_review');
  wrapper.unmount();
});
it('only sends a current native approval choice for atomic save and approve', async () => {
  const wrapper = mount(Component, options({ request: record }));
  await wrapper.find('input').setValue('2.00');
  await wrapper.find('textarea').setValue('Synthetic approve correction');
  await wrapper.find('select').setValue('approve');
  await wrapper.find('[data-confirm]').trigger('click');
  expect(wrapper.emitted('confirm')[0][0]).toMatchObject({
    mode: 'approve',
    changes: { discount_cents: 200 },
    step_code: 'private_review',
    delegation_id: null,
  });
  wrapper.unmount();
});
it.each(['-1', '1.001', 'garbage', '90071992547410'])(
  'blocks invalid or imprecise amount %s',
  async value => {
    const wrapper = mount(Component, options({ request: record }));
    await wrapper.find('input').setValue(value);
    await wrapper.find('textarea').setValue('Synthetic reason');
    expect(wrapper.find('[data-confirm]').attributes('disabled')).toBeDefined();
    await wrapper.find('[data-confirm]').trigger('click');
    expect(wrapper.emitted('confirm')).toBeUndefined();
    wrapper.unmount();
  }
);
it('blocks a stale source/version and retains the user input on recoverable server rejection', async () => {
  const wrapper = mount(Component, options({ request: record }));
  await wrapper.find('input').setValue('2');
  await wrapper.find('textarea').setValue('Synthetic reason');
  await wrapper.find('[data-confirm]').trigger('click');
  await wrapper.setProps({ busy: true });
  await wrapper.setProps({
    busy: false,
    error: 'Authority changed; reload the request',
  });
  expect(wrapper.find('input').element.value).toBe('2');
  expect(wrapper.find('[role="alert"]').text()).toContain('Authority changed');
  await wrapper.setProps({ request: { ...record, lock_version: 5 } });
  expect(wrapper.find('[data-confirm]').attributes('disabled')).toBeDefined();
  wrapper.unmount();
});
it('only exposes the adjustment entry point when the server returned native edit authorization', () => {
  const allowed = mount(RequestDetail, options({ request: record }));
  expect(
    allowed
      .findAll('button')
      .some(row => row.text() === 'Adjust permitted fields')
  ).toBe(true);
  allowed.unmount();
  const denied = mount(
    RequestDetail,
    options({ request: { ...record, adjustment: null } })
  );
  expect(
    denied
      .findAll('button')
      .some(row => row.text() === 'Adjust permitted fields')
  ).toBe(false);
  denied.unmount();
});
