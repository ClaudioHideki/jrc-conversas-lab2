import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { expect, it, vi } from 'vitest';
import locale from 'dashboard/i18n/locale/en/jrcApprovals.json';
import Component from '../ApprovalDecisionDialog.vue';
import RequestDetail from '../RequestDetail.vue';
import Origin from '../ApprovalOriginLink.vue';
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

it('keeps the exact native source available in the review and its confirmation popup', async () => {
  const config = options({
    request: { ...record, resource_type: 'JrcCrm::Contract', resource_id: 99 },
    context: { account_id: 17, scopes: [] },
  });
  config.global.stubs.RouterLink = {
    name: 'RouterLink',
    props: ['to'],
    template: '<a><slot /></a>',
  };
  const wrapper = mount(RequestDetail, config);
  await wrapper.get('textarea').setValue('Reviewed native source');
  await wrapper
    .findAll('button')
    .find(button => button.text().startsWith('Approve'))
    .trigger('click');
  await flushPromises();
  expect(wrapper.findAllComponents(Origin)).toHaveLength(2);
  const popup = wrapper.getComponent(Component);
  expect(
    popup.getComponent(Origin).getComponent({ name: 'RouterLink' }).props('to')
  ).toEqual({
    name: 'crm_contracts',
    params: { accountId: '17' },
    query: { contractId: '99' },
  });
  expect(wrapper.emitted('decide')).toBeUndefined();
  wrapper.unmount();
});

it('renders native stages and decisions without decision or adjustment controls in a read-only mirror', () => {
  const wrapper = mount(
    RequestDetail,
    options({
      request: {
        ...record,
        adjustment: { discount_cents: 1 },
        decisions: [
          {
            id: 1,
            decision: 'approved',
            actor_name: 'Synthetic reviewer',
            reason: 'Reviewed',
            cycle: 1,
          },
        ],
      },
      readOnly: true,
    })
  );
  expect(wrapper.text()).toContain('Synthetic reviewer');
  expect(wrapper.find('textarea').exists()).toBe(false);
  expect(wrapper.findComponent(Component).exists()).toBe(false);
  expect(
    wrapper
      .findAll('button')
      .some(button => button.text().startsWith('Approve'))
  ).toBe(false);
  expect(wrapper.emitted('decide')).toBeUndefined();
  expect(wrapper.emitted('adjust')).toBeUndefined();
  wrapper.unmount();
});

it('closes a pending native decision when the same detail switches to read-only', async () => {
  const wrapper = mount(RequestDetail, options({ request: record }));
  await wrapper.get('textarea').setValue('Reviewed');
  await wrapper
    .findAll('button')
    .find(button => button.text().startsWith('Approve'))
    .trigger('click');
  expect(wrapper.findComponent(Component).exists()).toBe(true);
  await wrapper.setProps({ readOnly: true });
  expect(wrapper.findComponent(Component).exists()).toBe(false);
  expect(wrapper.find('textarea').exists()).toBe(false);
  expect(wrapper.emitted('decide')).toBeUndefined();
  wrapper.unmount();
});

it('opens the scoped reviewed transfer source from the decision popup without casting a vote', async () => {
  const config = options({
    request: {
      ...record,
      origin: { kind: 'portfolio_distribution', review_id: 33 },
    },
  });
  config.global.stubs.DistributionApprovalOrigin = {
    template: '<p>Scoped synthetic transfer source</p>',
  };
  const wrapper = mount(RequestDetail, config);
  const source = wrapper.get('section[tabindex="-1"]').element;
  source.scrollIntoView = vi.fn(); // jsdom does not implement browser scrolling.
  await wrapper.get('textarea').setValue('Review transfer source');
  await wrapper
    .findAll('button')
    .find(button => button.text().startsWith('Approve'))
    .trigger('click');
  await flushPromises();
  const popup = wrapper.getComponent(Component);
  await popup.getComponent(Origin).get('button').trigger('click');
  await flushPromises();
  expect(wrapper.findComponent(Component).exists()).toBe(false);
  expect(wrapper.text()).toContain('Scoped synthetic transfer source');
  expect(source.scrollIntoView).toHaveBeenCalledWith({ block: 'start' });
  expect(wrapper.emitted('decide')).toBeUndefined();
  wrapper.unmount();
});
