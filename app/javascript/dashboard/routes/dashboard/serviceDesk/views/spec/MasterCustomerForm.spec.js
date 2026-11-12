import { computed, reactive, ref } from 'vue';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createRouter, createMemoryHistory } from 'vue-router';
import TicketFormView from '../TicketFormView.vue';
import sd from 'dashboard/i18n/locale/en/jrcServiceDesk.json';
import crm from 'dashboard/i18n/locale/en/crm.json';
const mocks = vi.hoisted(() => ({
  session: null,
  requesterContext: vi.fn(),
  relationshipChannels: vi.fn(),
  access: null,
}));
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => mocks.session,
}));
vi.mock('dashboard/api/serviceDesk', () => ({ default: mocks }));
vi.mock('dashboard/api/jrcRelationship', () => ({
  default: { channels: mocks.relationshipChannels },
}));
vi.mock('dashboard/routes/dashboard/jrcCustomers/useCustomerMaster', () => ({
  useCustomerMaster: () => ({ canAccess: computed(() => mocks.access.value) }),
}));
const Quick = {
  name: 'QuickTicketForm',
  props: ['customerContext', 'contextLoading'],
  emits: ['unitChange', 'advanced'],
  template: '<div />',
};
let wrapper;
let router;
beforeEach(() => {
  mocks.access = ref(true);
  mocks.relationshipChannels.mockReset();
  mocks.session = {
    accountId: ref('1'),
    userId: ref('7'),
    state: reactive({
      status: 'ready',
      context: {
        account_id: '1',
        user_id: '7',
        effective_permissions: ['jrc_service_desk_customers_view'],
        units: [
          {
            id: '10',
            permissions: { create_ticket: true },
            operator_company: { id: '20', name: 'Synthetic' },
          },
        ],
      },
    }),
    resource: () => ({ record: null }),
    resetResource: vi.fn(),
    operations: {
      mutation: () => ({ status: 'idle' }),
      dismissConfirmation: vi.fn(),
      cancel: vi.fn(),
    },
  };
  mocks.requesterContext.mockReset().mockResolvedValue({
    contract_version: 1,
    account_id: '1',
    person: {
      id: 33,
      company_id: 80,
      name: 'Canonical',
      requester_eligible: true,
    },
  });
});
afterEach(() => wrapper?.unmount());
async function render(
  query = { master_company_id: '80', master_contact_id: '33' }
) {
  router = createRouter({
    history: createMemoryHistory(),
    routes: [
      {
        name: 'new',
        path: '/:accountId/new',
        component: { template: '<div />' },
      },
    ],
  });
  await router.push({ name: 'new', params: { accountId: '1' }, query });
  wrapper = mount(TicketFormView, {
    global: {
      plugins: [
        router,
        createI18n({
          legacy: false,
          locale: 'en',
          messages: { en: { ...sd, ...crm } },
        }),
      ],
      stubs: { QuickTicketForm: Quick, InternalTicketForm: true },
    },
  });
  await flushPromises();
}
it('waits for the native unit selection, then supplies only the verified customer', async () => {
  await render();
  expect(mocks.requesterContext).not.toHaveBeenCalled();
  wrapper.findComponent(Quick).vm.$emit('unitChange', '10');
  await flushPromises();
  expect(mocks.requesterContext).toHaveBeenCalledWith(
    '1',
    { unitId: '10', companyId: '80', contactId: '33' },
    expect.any(AbortSignal)
  );
  expect(wrapper.findComponent(Quick).props('customerContext')).toMatchObject({
    company_id: '80',
    requester: { id: '33' },
  });
});
it('preserves master customer context when employee intake is also configured', async () => {
  mocks.session.state.context.units[0].internal_intake = {
    requester: { name: 'Synthetic' },
  };
  await render();
  expect(wrapper.find('internal-ticket-form-stub').exists()).toBe(false);
  wrapper.findComponent(Quick).vm.$emit('unitChange', '10');
  await flushPromises();
  expect(wrapper.findComponent(Quick).props('customerContext')).toMatchObject({
    company_id: '80',
    requester: { id: '33' },
  });
});
it('does not trust a unit supplied by the URL or an unauthorized unit event', async () => {
  await render({
    master_company_id: '80',
    unit_id: '999',
    user_id: '999',
    account_id: '999',
  });
  wrapper.findComponent(Quick).vm.$emit('unitChange', '999');
  await flushPromises();
  expect(mocks.requesterContext).not.toHaveBeenCalled();
  expect(wrapper.findComponent(Quick).props('customerContext')).toBeNull();
});
it('rejects a backend denial without substituting URL values', async () => {
  mocks.requesterContext.mockRejectedValue({ response: { status: 403 } });
  await render();
  wrapper.findComponent(Quick).vm.$emit('unitChange', '10');
  await flushPromises();
  expect(wrapper.findComponent(Quick).props('customerContext')).toBeNull();
  expect(wrapper.text()).toContain(
    crm.CRM.CUSTOMER_MASTER_360.TICKET_CONTEXT_DENIED
  );
});
it.each(['account', 'user', 'role'])(
  'discards an in-flight response on %s change',
  async change => {
    let finish;
    mocks.requesterContext.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    await render();
    wrapper.findComponent(Quick).vm.$emit('unitChange', '10');
    await flushPromises();
    const finishOld = finish;
    if (change === 'account') mocks.session.accountId.value = '2';
    if (change === 'user') mocks.session.userId.value = '8';
    if (change === 'role') mocks.access.value = false;
    await flushPromises();
    // The old response remains untrusted even when the transport ignores AbortSignal.
    finishOld({
      contract_version: 1,
      account_id: '1',
      person: { id: 33, company_id: 80, requester_eligible: true },
    });
    await flushPromises();
    expect(wrapper.findComponent(Quick).props('customerContext')).toBeNull();
  }
);

it('keeps employee-only intake isolated from master and relationship URL seeds', async () => {
  mocks.session.state.context.units[0].employee_only = true;
  await render({
    master_company_id: '80',
    master_contact_id: '33',
    relationship_assignment_id: '44',
    requester_id: '33',
  });
  expect(wrapper.find('internal-ticket-form-stub').exists()).toBe(true);
  expect(wrapper.findComponent(Quick).exists()).toBe(false);
  expect(mocks.requesterContext).not.toHaveBeenCalled();
  expect(mocks.relationshipChannels).not.toHaveBeenCalled();
});
it('discards a pending master response across an employee-only profile transition', async () => {
  let finish;
  mocks.requesterContext.mockImplementation(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  wrapper.findComponent(Quick).vm.$emit('unitChange', '10');
  await flushPromises();
  const finishOld = finish;
  mocks.session.state.context.units[0].employee_only = true;
  await flushPromises();
  expect(wrapper.find('internal-ticket-form-stub').exists()).toBe(true);
  mocks.session.state.context.units[0].employee_only = false;
  await flushPromises();
  finishOld({
    contract_version: 1,
    account_id: '1',
    person: { id: 33, company_id: 80, requester_eligible: true },
  });
  await flushPromises();
  expect(wrapper.findComponent(Quick).props('customerContext')).toBeNull();
});
