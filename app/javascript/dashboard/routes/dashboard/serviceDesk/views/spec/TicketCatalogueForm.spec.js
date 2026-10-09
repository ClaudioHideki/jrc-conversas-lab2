import { afterEach, describe, expect, it, vi } from 'vitest';
import { reactive, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createRouter, createMemoryHistory } from 'vue-router';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import sourceMessages from 'dashboard/i18n/locale/en/jrcServiceDesk.json';
import {
  createServiceDeskSession,
  createSessionState,
} from '../../helpers/session';
import {
  createOperationalSession,
  createOperationalState,
} from '../../helpers/operationalSession';
import {
  SERVICE_DESK_ROUTES,
  serviceDeskRouteName,
} from '../../routeDefinitions';
import {
  contextPayload,
  identity,
  collection,
  ticket,
  detail,
} from '../../__tests__/fixtures';
import TicketFormView from '../TicketFormView.vue';
import LookupSelect from '../../components/LookupSelect.vue';
import ServiceDefinitionSelect from '../../components/ServiceDefinitionSelect.vue';
import CompanyPicker from 'dashboard/routes/dashboard/jrcCustomers/components/CompanyPicker.vue';
const mocks = vi.hoisted(() => ({
  session: null,
  services: vi.fn(),
  catalogueForm: vi.fn(),
}));
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => mocks.session,
}));
vi.mock('dashboard/api/serviceDeskLifecycle', () => ({ default: mocks }));
vi.mock('dashboard/routes/dashboard/jrcCustomers/useCustomerMaster', () => ({
  useCustomerMaster: () => ({ canAccess: ref(true) }),
}));
const Select = {
  props: ['modelValue', 'options', 'disabled'],
  emits: ['update:modelValue'],
  template:
    '<select :value="modelValue" :disabled="disabled" @change="$emit(\'update:modelValue\', $event.target.value)"><option v-for="o in options" :key="o.value" :value="o.value">{{ o.label }}</option></select>',
};
const Button = {
  props: ['label', 'type', 'disabled'],
  template:
    '<button :type="type || \'button\'" :disabled="disabled">{{ label }}</button>',
};
const Input = {
  props: ['label', 'modelValue', 'disabled'],
  emits: ['update:modelValue'],
  template:
    '<label>{{ label }}<input :value="modelValue" :disabled="disabled" @input="$emit(\'update:modelValue\', $event.target.value)" /></label>',
};
const field = {
  key: 'asset_tag',
  label: 'Asset tag',
  type: 'text',
  required: true,
};
let wrapper;
afterEach(() => {
  wrapper?.unmount();
  mocks.session?.operations.clear();
  mocks.session?.dispose();
  vi.unstubAllGlobals();
});
async function render() {
  vi.stubGlobal('crypto', { randomUUID: () => 'r3-ticket-test-key' });
  const context = contextPayload({
    effective_permissions: ['jrc_service_desk_customers_view'],
  });
  context.units[0].initial_status = { id: '1', name: 'Initial' };
  context.capabilities.ticket_types = { index: true };
  context.capabilities.contracts = { index: true };
  const catalogue = {
    id: '40',
    account_id: '1',
    unit_id: '10',
    name: 'Configured IT',
    active: true,
    code: 'it',
    form_fields: [],
  };
  mocks.services.mockResolvedValue({
    contract_version: 1,
    account_id: '1',
    unit_id: '10',
    items: [catalogue],
    meta: { total: 1, page: 1, per_page: 20 },
  });
  mocks.catalogueForm.mockImplementation(async (_account, params) => ({
    contract_version: 1,
    account_id: '1',
    unit_id: '10',
    revision: 'a'.repeat(64),
    form_fields: [field],
    service: params.service_id ? { id: '40', name: 'Configured IT' } : null,
    category: { id: '4', name: 'Configured category' },
    ticket_type: { id: '5', name: 'Configured type' },
    subcategory: null,
    defaults: {
      priority_id: '2',
      priority: { id: '2', name: 'Configured priority' },
      queue_id: null,
      assignee_account_user_id: null,
    },
    allowed_company_ids: ['80'],
    allowed_contract_ids: ['90'],
  }));
  const base = createServiceDeskSession(
    {
      context: async () => context,
      list: async (_account, resource) => {
        const ids = {
          requesters: '33',
          priorities: '2',
          categories: '4',
          ticket_types: '5',
          contracts: '90',
          assignees: '7',
          queues: '6',
          teams: '8',
        };
        return collection([
          {
            id: ids[resource],
            account_id: '1',
            unit_id: '10',
            name: `Chosen ${resource}`,
            permissions: { show: true },
            ...(resource === 'contracts'
              ? { company_id: '80', contact_id: '33' }
              : {}),
            ...(resource === 'categories'
              ? { parent_id: null, form_fields: [] }
              : {}),
            ...(resource === 'ticket_types' ? { form_fields: [] } : {}),
          },
        ]);
      },
    },
    reactive(createSessionState())
  );
  const create = vi.fn(async () => ({
    contract_version: 1,
    account_id: '1',
    ticket_id: '20',
    operation: 'create',
    applied: true,
  }));
  const operations = createOperationalSession(
    {
      create,
      ticket: async () =>
        detail(
          ticket({
            title: 'Native issue',
            description: '',
            lock_version: 0,
            company: { id: '80', name: 'Chosen company' },
            service: { id: '40', name: 'Configured IT' },
            category: { id: '4', name: 'Configured category' },
            ticket_type: { id: '5', name: 'Configured type' },
            contract: { id: '90', name: 'Chosen contract' },
            catalogue_form_fields: [field],
            service_fields: { asset_tag: 'R3-device' },
          })
        ),
    },
    base,
    reactive(createOperationalState())
  );
  mocks.session = {
    ...base,
    operations,
    accountId: ref('1'),
    userId: ref('7'),
    enabled: ref(true),
  };
  await base.start(identity);
  const router = createRouter({
    history: createMemoryHistory(),
    routes: SERVICE_DESK_ROUTES.map(row => ({
      path: `/app/accounts/:accountId/service-desk/${row.path}`,
      name: serviceDeskRouteName(row.key),
      component: { template: '<div />' },
    })),
  });
  await router.push({
    name: serviceDeskRouteName('new'),
    params: { accountId: '1' },
  });
  await router.isReady();
  wrapper = mount(TicketFormView, {
    props: { screen: 'new' },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          fallbackLocale: 'en',
          messages: { pt_BR: messages, en: sourceMessages },
        }),
        router,
        createStore({ getters: { getCurrentUser: () => ({ id: '7' }) } }),
      ],
      stubs: {
        Input,
        Select,
        Button,
        CompanyPicker: true,
        Icon: true,
        Spinner: true,
      },
    },
  });
  await wrapper.findAll('select')[1].setValue('10');
  await flushPromises();
  await wrapper
    .findAllComponents(LookupSelect)
    .find(row => row.props('resource') === 'requesters')
    .find('select')
    .setValue('33');
  await wrapper
    .findAllComponents(Input)
    .find(row => row.props('label') === messages.JRC_SERVICE_DESK.FIELDS.title)
    .find('input')
    .setValue('Native issue');
  await wrapper.findAll('.sd-wizard-step')[2].trigger('click');
  await flushPromises();
  await wrapper
    .findComponent(ServiceDefinitionSelect)
    .find('select')
    .setValue('40');
  await flushPromises();
  return { create, router };
}
describe('R3 native ticket wizard uses configured defaults with explicit customer/contract authority', () => {
  it('does not choose the first company/contract or submit before the configured required answer', async () => {
    const { create } = await render();
    await wrapper.findAll('.sd-wizard-step')[0].trigger('click');
    expect(wrapper.findComponent(CompanyPicker).props('modelValue')).toBeNull();
    await wrapper.findAll('.sd-wizard-step')[2].trigger('click');
    const contract = wrapper
      .findAllComponents(LookupSelect)
      .find(row => row.props('resource') === 'contracts');
    expect(contract.props('modelValue')).toBe('');
    expect(mocks.catalogueForm.mock.calls.at(-1)[1]).toMatchObject({
      service_id: '40',
      category_id: '4',
      ticket_type_id: '5',
    });
    await wrapper.findAll('.sd-wizard-step')[3].trigger('click');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(create).not.toHaveBeenCalled();
  });
  it('sends the explicitly chosen canonical customer/contract and merged answers through native write/readback', async () => {
    const { create, router } = await render();
    await wrapper.findAll('.sd-wizard-step')[0].trigger('click');
    wrapper.findComponent(CompanyPicker).vm.$emit('update:modelValue', '80');
    await flushPromises();
    await wrapper.findAll('.sd-wizard-step')[2].trigger('click');
    await flushPromises();
    const contract = wrapper
      .findAllComponents(LookupSelect)
      .find(row => row.props('resource') === 'contracts');
    await contract.find('select').setValue('90');
    await wrapper
      .findAll('label')
      .find(row => row.text().startsWith('Asset tag'))
      .find('input')
      .setValue('R3-device');
    await flushPromises();
    await wrapper.findAll('.sd-wizard-step')[3].trigger('click');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(create).toHaveBeenCalledTimes(1);
    expect(create.mock.calls[0][1].ticket).toMatchObject({
      company_id: '80',
      contract_id: '90',
      ticket_type_id: '5',
      category_id: '4',
      service_fields: { asset_tag: 'R3-device' },
    });
    expect(router.currentRoute.value.name).toBe(serviceDeskRouteName('new'));
    expect(
      wrapper.find('[data-testid="ticket-created-receipt"]').exists()
    ).toBe(true);
    expect(wrapper.find('[data-testid="ticket-protocol"]').text()).toContain(
      'TEST-20'
    );
    await wrapper.find('[data-testid="open-created-ticket"]').trigger('click');
    await flushPromises();
    expect(router.currentRoute.value.name).toBe(serviceDeskRouteName('detail'));
  });
});
