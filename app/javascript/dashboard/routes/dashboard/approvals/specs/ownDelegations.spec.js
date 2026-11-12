import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { beforeEach, expect, it, vi } from 'vitest';
import locale from 'dashboard/i18n/locale/en/jrcApprovals.json';
import Component from '../OwnDelegationView.vue';
import Dialog from '../ApprovalDecisionDialog.vue';
import { decisionChoices } from '../model';
const get = vi.fn();
const context = {
  account_id: 1,
  member_id: 11,
  scopes: [
    {
      issuer_company_id: 2,
      business_unit_id: 3,
      company_name: 'Synthetic issuer',
      unit_name: 'Unit A',
      capabilities: ['delegate', 'decide'],
    },
  ],
};
const Button = {
  props: ['label', 'disabled', 'type'],
  template:
    '<button :type="type || \'button\'" :disabled="disabled">{{ label }}</button>',
};
const options = props => ({
  props,
  global: {
    plugins: [
      createI18n({ legacy: false, locale: 'en', messages: { en: locale } }),
    ],
    stubs: { Button },
  },
});
beforeEach(() => {
  get.mockReset();
  get.mockResolvedValue({
    data: [{ id: 12, name: 'Synthetic scoped substitute' }],
    headers: { 'x-total-count': '1', 'x-page': '1', 'x-per-page': '100' },
  });
  vi.stubGlobal('axios', { get });
});
it('creates only own scope/action/window intent without a client principal or automatic actions', async () => {
  const wrapper = mount(Component, options({ context, rows: [] }));
  await wrapper.findAll('select')[0].setValue('2:3');
  await flushPromises();
  expect(get).toHaveBeenCalledWith(
    '/api/v1/accounts/1/approvals/own_delegations/recipients',
    {
      params: {
        issuer_company_id: 2,
        business_unit_id: 3,
        page: 1,
        per_page: 100,
      },
    }
  );
  await wrapper.findAll('select')[1].setValue('12');
  const dates = wrapper.findAll('input[type="datetime-local"]');
  await dates[0].setValue('2050-01-01T09:00');
  await dates[1].setValue('2050-01-10T18:00');
  await wrapper.find('textarea').setValue(' Synthetic vacation coverage ');
  expect(
    wrapper.find('button[type="submit"]').attributes('disabled')
  ).toBeDefined();
  await wrapper.find('input[type="checkbox"]').setValue(true);
  await wrapper.find('form').trigger('submit');
  expect(wrapper.emitted('create')[0][0]).toMatchObject({
    delegate_id: 12,
    issuer_company_id: 2,
    business_unit_id: 3,
    reason: 'Synthetic vacation coverage',
    actions: ['approved'],
  });
  expect(wrapper.emitted('create')[0][0]).not.toHaveProperty('principal_id');
  expect(wrapper.emitted('create')[0][0].starts_at).toMatch(/Z$/);
  await wrapper.find('textarea').setValue('');
  expect(wrapper.find('textarea').attributes('required')).toBeUndefined();
  await wrapper.find('form').trigger('submit');
  expect(wrapper.emitted('create')[1][0].reason).toBe('');
  wrapper.unmount();
});
it('hides the grant form without both own-delegation and decision capabilities but keeps received history', () => {
  const wrapper = mount(
    Component,
    options({
      context: {
        ...context,
        scopes: [{ ...context.scopes[0], capabilities: ['decide'] }],
      },
      rows: [
        {
          id: 1,
          principal_name: 'Principal',
          delegate_name: 'Recipient',
          reason: 'Synthetic',
          starts_at: '2020-01-01Z',
          ends_at: '2050-01-01Z',
          can_revoke: false,
        },
      ],
    })
  );
  expect(wrapper.find('form').exists()).toBe(false);
  expect(wrapper.text()).toContain('Principal');
  expect(wrapper.findAll('button')).toHaveLength(0);
  wrapper.unmount();
});
it('discards stale recipient responses when switching accounts and resets the prior identity fields', async () => {
  let resolve;
  get.mockImplementationOnce(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  const wrapper = mount(Component, options({ context, rows: [] }));
  await wrapper.findAll('select')[0].setValue('2:3');
  await wrapper.setProps({ context: { ...context, account_id: 9 } });
  resolve({
    data: [{ id: 88, name: 'Former-account private name' }],
    headers: {},
  });
  await flushPromises();
  expect(wrapper.text()).not.toContain('Former-account private name');
  expect(wrapper.findAll('select')[0].element.value).toBe('');
  expect(wrapper.findAll('select')[1].element.value).toBe('');
  wrapper.unmount();
});
it('offers revocation only for the owned active grant id and preserves other-party history', async () => {
  const wrapper = mount(
    Component,
    options({
      context,
      rows: [
        {
          id: 7,
          principal_name: 'Principal',
          delegate_name: 'Recipient',
          starts_at: '2020-01-01Z',
          ends_at: '2050-01-01Z',
          can_revoke: true,
          revoked: false,
        },
        {
          id: 8,
          principal_name: 'Another principal',
          delegate_name: 'Recipient',
          starts_at: '2020-01-01Z',
          ends_at: '2050-01-01Z',
          can_revoke: false,
          revoked: false,
        },
      ],
    })
  );
  const button = wrapper
    .findAll('button')
    .find(row => row.text() === 'Revoke my delegation');
  await button.trigger('click');
  expect(wrapper.emitted('revoke')).toEqual([[7]]);
  wrapper.unmount();
});
it('preserves own delegation identity through native decision choices and confirmation', async () => {
  const dto = {
    id: 4,
    state: 'pending',
    lock_version: 2,
    allowed_decisions: [
      {
        step_code: 'review',
        choices: [
          {
            delegation_id: null,
            own_delegation_id: 55,
            principal_name: 'Scoped principal',
            actions: ['approved'],
          },
        ],
      },
    ],
  };
  const choice = decisionChoices(dto)[0];
  const DialogStub = {
    props: ['disableConfirmButton'],
    emits: ['confirm'],
    setup(_, { expose }) {
      expose({ open: vi.fn() });
    },
    template:
      '<section><slot /><button :disabled="disableConfirmButton" @click="$emit(\'confirm\')">Confirm</button></section>',
  };
  const config = options({
    request: dto,
    choice,
    reason: 'Synthetic global authority vote',
  });
  config.global.stubs.Dialog = DialogStub;
  const wrapper = mount(Dialog, config);
  expect(wrapper.text()).toContain('Scoped principal');
  await wrapper.find('button').trigger('click');
  expect(wrapper.emitted('confirm')[0][0]).toMatchObject({
    own_delegation_id: 55,
    delegation_id: null,
    step_code: 'review',
  });
  wrapper.unmount();
});
