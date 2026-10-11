import { afterEach, describe, expect, it, vi } from 'vitest';
import { reactive, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createRouter, createMemoryHistory } from 'vue-router';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import {
  createServiceDeskSession,
  createSessionState,
} from '../helpers/session';
import {
  createOperationalSession,
  createOperationalState,
} from '../helpers/operationalSession';
import {
  ticketListContext,
  ticketListReturn,
} from '../helpers/ticketNavigation';
import {
  contextPayload,
  identity,
  collection,
  ticket,
  detail,
  deferred,
} from './fixtures';
import { SERVICE_DESK_ROUTES, serviceDeskRouteName } from '../routeDefinitions';
const holder = vi.hoisted(() => ({ session: null }));
vi.mock('../composables/useServiceDesk', () => ({
  useServiceDesk: () => holder.session,
}));
vi.mock('dashboard/routes/dashboard/jrcCustomers/useCustomerMaster', () => ({
  useCustomerMaster: () => ({ canAccess: ref(false) }),
}));
import TicketListView from '../views/TicketListView.vue';
import TicketDetailView from '../views/TicketDetailView.vue';
import TicketFormView from '../views/TicketFormView.vue';
import TicketSummary from '../components/TicketSummary.vue';

const Button = {
  props: ['label', 'type', 'disabled'],
  template:
    '<button :type="type || \'button\'" :disabled="disabled">{{ label }}</button>',
};
const Input = {
  props: ['modelValue', 'label', 'disabled'],
  emits: ['update:modelValue'],
  template:
    '<label>{{ label }}<input :disabled="disabled" :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" /></label>',
};
const TextArea = {
  props: ['modelValue', 'label', 'disabled'],
  emits: ['update:modelValue'],
  template:
    '<label>{{ label }}<textarea :disabled="disabled" :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" /></label>',
};
const stubs = {
  Button,
  Input,
  TextArea,
  Icon: true,
  Select: true,
  Spinner: true,
  TicketFilters: true,
  LiveKpis: true,
  ClaimNext: true,
  PaginationFooter: true,
  TabBar: true,
  TicketTable: {
    emits: ['open', 'preview'],
    template:
      "<div><button @click=\"$emit('open', '20')\">Open row</button><button @click=\"$emit('preview', '20')\">Preview row</button><button @click=\"$emit('preview', '21')\">Preview other</button></div>",
  },
  OperationsLinks: true,
  CustomerContextPanel: true,
  TicketCockpit: true,
  LifecyclePanel: true,
  SlaSnapshotEditor: true,
  TicketOperations: true,
  TicketActivity: true,
  ScopeBar: true,
  LookupSelect: true,
  ServiceDefinitionSelect: true,
  CompanyPicker: true,
  CatalogueAnswers: true,
  ImpactUrgencySelect: true,
};
let wrapper;
afterEach(() => {
  wrapper?.unmount();
  holder.session?.operations?.clear();
  holder.session?.dispose();
  holder.session = null;
});
async function render(
  component,
  screen,
  row = ticket(),
  overrides = {},
  operationClient = null
) {
  const client = {
    context: async () => contextPayload(),
    list: async () => collection(),
    ticket: async () => detail(row),
    ...overrides,
  };
  const base = createServiceDeskSession(client, reactive(createSessionState()));
  holder.session = {
    ...base,
    operations: operationClient
      ? createOperationalSession(
          operationClient,
          base,
          reactive(createOperationalState())
        )
      : null,
    accountId: ref('1'),
    userId: ref('7'),
    enabled: ref(true),
  };
  await base.start(identity);
  const router = createRouter({
    history: createMemoryHistory(),
    routes: SERVICE_DESK_ROUTES.map(entry => ({
      path: `/app/accounts/:accountId/service-desk${entry.path ? `/${entry.path}` : ''}`,
      name: serviceDeskRouteName(entry.key),
      component: { template: '<div />' },
    })),
  });
  await router.push({
    name: serviceDeskRouteName(screen),
    params: {
      accountId: '1',
      ...(['detail', 'edit'].includes(screen) ? { ticketId: row.id } : {}),
    },
    query:
      screen === 'tickets'
        ? { q: 'PABX' }
        : ticketListContext('mine', { q: 'PABX', page: 3 }),
  });
  await router.isReady();
  wrapper = mount(component, {
    props: { screen },
    global: {
      plugins: [
        router,
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: messages },
        }),
        createStore({
          getters: { 'accounts/isFeatureEnabledonAccount': () => () => false },
        }),
      ],
      stubs,
    },
  });
  await flushPromises();
  return { router, client };
}
const click = async label => {
  const button = wrapper.findAll('button').find(b => b.text() === label);
  expect(button, label).toBeTruthy();
  await button.trigger('click');
  await flushPromises();
};

describe('ticket details, preview and authorized editing', () => {
  it('opens the corresponding detail with the list context', async () => {
    const { router } = await render(TicketListView, 'tickets');
    await click('Open row');
    expect(router.currentRoute.value.name).toBe(serviceDeskRouteName('detail'));
    expect(router.currentRoute.value.params.ticketId).toBe('20');
    expect(ticketListReturn(router.currentRoute.value.query).query.q).toBe(
      'PABX'
    );
  });
  it('previews actual description, classification, requester, opening and available SLA', async () => {
    const row = ticket({
      description: 'Description from the selected ticket',
      opened_at: '2026-09-24T10:00:00Z',
      category: { id: '4', name: 'Network' },
      subcategory: { id: '5', name: 'Router' },
      ticket_type: { id: '6', name: 'Incident' },
      requester: {
        id: '33',
        name: 'Requester',
        phone_number: '+5511999990001',
      },
      sla: {
        state: 'calculated',
        first_response_due_at: '2026-09-25T13:00:00Z',
        resolution_due_at: '2026-09-25T17:00:00Z',
      },
    });
    await render(TicketListView, 'tickets', row);
    await click('Preview row');
    [
      'TEST-20',
      row.title,
      row.description,
      'Router',
      'Incident',
      '+5511999990001',
      'Aberto em',
      '24/09/2026',
    ].forEach(value => expect(wrapper.text()).toContain(value));
    expect(
      wrapper.findComponent(TicketSummary).props('ticket').sla.resolution_due_at
    ).toBe(row.sla.resolution_due_at);
  });
  it('discards a previous preview while another ticket is loading, including late responses', async () => {
    const slow = deferred();
    await render(TicketListView, 'tickets', ticket(), {
      ticket: async (_account, id) =>
        id === '20'
          ? slow.promise
          : detail(ticket({ id: '21', title: 'Second ticket' })),
    });
    await click('Preview row');
    await click('Preview other');
    expect(wrapper.text()).toContain('Second ticket');
    slow.resolve(detail(ticket({ title: 'Stale first ticket' })));
    await flushPromises();
    expect(wrapper.text()).not.toContain('Stale first ticket');
  });
  it('renders full description and navigates authorized editing then returns to my queue', async () => {
    const { router } = await render(TicketDetailView, 'detail');
    expect(wrapper.text()).toContain('Test-only text');
    await click('Editar chamado');
    expect(router.currentRoute.value.name).toBe(serviceDeskRouteName('edit'));
    expect(router.currentRoute.value.params.ticketId).toBe('20');
    await router.push({
      name: serviceDeskRouteName('detail'),
      params: { accountId: '1', ticketId: '20' },
      query: router.currentRoute.value.query,
    });
    await click('Chamados');
    expect(router.currentRoute.value.name).toBe(serviceDeskRouteName('mine'));
    expect(router.currentRoute.value.query).toMatchObject({
      q: 'PABX',
      page: '3',
      mine: 'true',
    });
  });
  it('does not offer editing when the backend denies it', async () => {
    const row = ticket({
      permissions: { ...ticket().permissions, update: false },
    });
    await render(TicketDetailView, 'detail', row);
    expect(
      wrapper.findAll('button').some(b => b.text() === 'Editar chamado')
    ).toBe(false);
  });
  it('denies a direct editing route for a read-only ticket', async () => {
    await render(
      TicketFormView,
      'edit',
      ticket({ permissions: { ...ticket().permissions, update: false } })
    );
    expect(wrapper.find('form').exists()).toBe(false);
    expect(wrapper.text()).toContain(messages.JRC_SERVICE_DESK.STATES.denied);
  });
  it('rejects details from another Account rather than rendering them', async () => {
    await render(
      TicketDetailView,
      'detail',
      ticket({ account_id: '2', description: 'Foreign secret' })
    );
    expect(wrapper.text()).not.toContain('Foreign secret');
    expect(holder.session.state.status).toBe('invalid_contract');
  });
  it('shows save success only for a confirmed readback of this ticket and Account', async () => {
    const row = ticket({ lock_version: 1 });
    await render(TicketDetailView, 'detail', row);
    let saved = { ...row, account_id: '2' };
    holder.session.operations = {
      mutation: () => ({ status: 'confirmed', ticket: saved }),
    };
    await holder.session.load('ticket:detail', 'tickets', {}, row.id);
    await flushPromises();
    expect(wrapper.text()).not.toContain(
      messages.JRC_SERVICE_DESK.OPS.STATUS.confirmed
    );
    saved = { ...row };
    await holder.session.load('ticket:detail', 'tickets', {}, row.id);
    await flushPromises();
    expect(wrapper.text()).toContain(
      messages.JRC_SERVICE_DESK.OPS.STATUS.confirmed
    );
    saved = { ...row, id: '21' };
    await holder.session.load('ticket:detail', 'tickets', {}, row.id);
    await flushPromises();
    expect(wrapper.text()).not.toContain(
      messages.JRC_SERVICE_DESK.OPS.STATUS.confirmed
    );
    holder.session.operations = null;
  });
  it('keeps the current form and values when validation rejects saving', async () => {
    const row = ticket({ lock_version: 0 });
    const update = vi.fn(async () => {
      const error = new Error('Synthetic validation rejection');
      error.response = { status: 422 };
      throw error;
    });
    const { router } = await render(
      TicketFormView,
      'edit',
      row,
      {},
      { update, ticket: async () => detail(row) }
    );
    const title = wrapper
      .findAll('input')
      .find(input => input.element.value === row.title);
    await title.setValue('Keep rejected draft');
    await click('Próxima etapa');
    await click('Próxima etapa');
    await click('Próxima etapa');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(update).toHaveBeenCalledOnce();
    expect(router.currentRoute.value.name).toBe(serviceDeskRouteName('edit'));
    expect(wrapper.text()).toContain('Keep rejected draft');
    expect(wrapper.text()).toContain(
      messages.JRC_SERVICE_DESK.OPS.STATUS.invalid_input
    );
  });
  it('loads existing values and saves only editable fields with optional assignments empty', async () => {
    const row = ticket({
      lock_version: 0,
      category: null,
      ticket_type: null,
      subcategory: null,
      team: null,
      assignee: null,
      queue: null,
    });
    let persisted = row;
    const update = vi.fn(async (_account, payload) => {
      persisted = {
        ...row,
        title: payload.ticket.title,
        description: payload.ticket.description,
        lock_version: 1,
      };
      return {
        contract_version: 1,
        account_id: '1',
        ticket_id: '20',
        operation: 'update',
        applied: true,
      };
    });
    const { router } = await render(
      TicketFormView,
      'edit',
      row,
      {},
      { update, ticket: async () => detail(persisted) }
    );
    expect(wrapper.find('textarea').element.value).toBe(row.description);
    const title = wrapper
      .findAll('input')
      .find(input => input.element.value === row.title);
    await title.setValue('Persisted new title');
    await click('Próxima etapa');
    await click('Próxima etapa');
    await click('Próxima etapa');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(update).toHaveBeenCalledOnce();
    const payload = update.mock.calls[0][1];
    expect(payload).toMatchObject({
      ticketId: '20',
      expected_lock_version: 0,
      ticket: { title: 'Persisted new title', description: row.description },
    });
    expect(payload.ticket).not.toHaveProperty('team_id');
    expect(payload.ticket).not.toHaveProperty('assignee_account_user_id');
    expect(router.currentRoute.value.name).toBe(serviceDeskRouteName('detail'));
    expect(ticketListReturn(router.currentRoute.value.query).query.page).toBe(
      3
    );
  });
});
