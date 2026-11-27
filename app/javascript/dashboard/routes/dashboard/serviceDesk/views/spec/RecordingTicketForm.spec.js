import { computed, reactive, ref } from 'vue';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { shallowMount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createRouter, createMemoryHistory } from 'vue-router';
import TicketFormView from '../TicketFormView.vue';
import sd from 'dashboard/i18n/locale/en/jrcServiceDesk.json';
import crm from 'dashboard/i18n/locale/en/crm.json';
import cc from 'dashboard/i18n/locale/en/jrcContactCenter.json';

const mocks = vi.hoisted(() => ({
  session: null,
  access: null,
  requesterContext: vi.fn(),
  recordingTicketIntake: vi.fn(),
}));
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => mocks.session,
}));
vi.mock('dashboard/api/serviceDesk', () => ({
  default: { requesterContext: mocks.requesterContext },
}));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { recordingTicketIntake: mocks.recordingTicketIntake },
}));
vi.mock('dashboard/routes/dashboard/jrcCustomers/useCustomerMaster', () => ({
  useCustomerMaster: () => ({ canAccess: computed(() => mocks.access.value) }),
}));
const dto = () => ({
  contract_version: 1,
  account_id: '1',
  user_id: '7',
  recording_id: '8',
  call_session_id: '9',
  call_id: 'SYNTHETIC actual source',
  contact_id: '33',
  service_desk_unit_id: '10',
});
let wrapper;
let router;
beforeEach(() => {
  mocks.access = ref(true);
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
            operator_company: { id: '20', name: 'SYNTHETIC operator' },
            initial_status: { id: '1' },
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
      write: vi.fn(),
    },
  };
  mocks.recordingTicketIntake.mockReset().mockResolvedValue({ data: dto() });
  mocks.requesterContext.mockReset();
  mocks.requesterContext.mockResolvedValue({
    contract_version: 1,
    account_id: '1',
    person: {
      id: 33,
      company_id: 80,
      name: 'SYNTHETIC native caller',
      requester_eligible: true,
    },
  });
});
afterEach(() => wrapper?.unmount());
const render = async (query = { recording_id: '8' }) => {
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
  wrapper = shallowMount(TicketFormView, {
    global: {
      stubs: { Panel: { template: '<section><slot /></section>' } },
      plugins: [
        router,
        createI18n({
          legacy: false,
          locale: 'en',
          messages: { en: { ...sd, ...crm, ...cc } },
        }),
      ],
    },
  });
  await flushPromises();
};

it('uses the existing advanced native form with the server-authorized unit and requester', async () => {
  await render();
  expect(wrapper.find('[data-recording-ticket-origin]').exists()).toBe(true);
  expect(wrapper.findComponent({ name: 'InternalTicketForm' }).exists()).toBe(
    false
  );
  expect(wrapper.findComponent({ name: 'QuickTicketForm' }).exists()).toBe(
    false
  );
  expect(wrapper.getComponent({ name: 'ScopeBar' }).props()).toMatchObject({
    unitId: '10',
    disabled: true,
  });
  expect(
    wrapper.getComponent({ name: 'RequesterSelect' }).props()
  ).toMatchObject({ modelValue: '33', disabled: true });
  expect(mocks.session.operations.write).not.toHaveBeenCalled();
});
it('does not use actor, unit or master-customer query parameters to override the native recording origin', async () => {
  await render({
    recording_id: '8',
    user_id: '999',
    unit_id: '999',
    master_company_id: '999',
    master_contact_id: '999',
  });
  expect(mocks.requesterContext).toHaveBeenCalledWith(
    '1',
    { unitId: '10', companyId: null, contactId: '33' },
    expect.any(AbortSignal)
  );
  expect(wrapper.getComponent({ name: 'ScopeBar' }).props('unitId')).toBe('10');
  expect(
    wrapper.getComponent({ name: 'RequesterSelect' }).props('modelValue')
  ).toBe('33');
});
it('blocks the selected origin rather than falling through to a quick or employee-only intake after denial', async () => {
  mocks.recordingTicketIntake.mockRejectedValueOnce({
    response: { status: 403 },
  });
  await render();
  expect(wrapper.find('[data-recording-ticket-denied]').exists()).toBe(true);
  expect(wrapper.find('form').exists()).toBe(false);
  expect(wrapper.findComponent({ name: 'InternalTicketForm' }).exists()).toBe(
    false
  );
  expect(wrapper.findComponent({ name: 'QuickTicketForm' }).exists()).toBe(
    false
  );
  expect(mocks.session.operations.write).not.toHaveBeenCalled();
});
it('abandons the previous actor source and requester when the active profile changes', async () => {
  await render();
  mocks.session.userId.value = '12';
  await flushPromises();
  expect(wrapper.find('[data-recording-ticket-origin]').exists()).toBe(false);
  expect(wrapper.find('form').exists()).toBe(false);
  expect(mocks.session.operations.write).not.toHaveBeenCalled();
});

it('does not expose a previous actor draft when another authorized actor uses the same unit and contact', async () => {
  await render();
  const title = () =>
    wrapper
      .findAllComponents({ name: 'Input' })
      .find(field => field.props('label') === sd.JRC_SERVICE_DESK.FIELDS.title);
  title().vm.$emit(
    'update:modelValue',
    'SYNTHETIC private previous actor draft'
  );
  await flushPromises();
  expect(title().props('modelValue')).toBe(
    'SYNTHETIC private previous actor draft'
  );
  mocks.recordingTicketIntake.mockResolvedValue({
    data: { ...dto(), user_id: '12' },
  });
  mocks.session.userId.value = '12';
  mocks.session.state.context.user_id = '12';
  await flushPromises();
  expect(wrapper.find('[data-recording-ticket-origin]').exists()).toBe(true);
  expect(title().props('modelValue')).toBe('');
});
it('does not change or fetch a recording source during ordinary native intake', async () => {
  await render({});
  expect(mocks.recordingTicketIntake).not.toHaveBeenCalled();
  expect(wrapper.findComponent({ name: 'InternalTicketForm' }).exists()).toBe(
    true
  );
  expect(wrapper.find('[data-recording-ticket-origin]').exists()).toBe(false);
});
