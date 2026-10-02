import { afterEach, describe, it, expect, vi } from 'vitest';
import { reactive, ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import { createRouter, createMemoryHistory } from 'vue-router';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import { createServiceDeskSession, createSessionState } from '../helpers/session.js';
import { createOperationalSession, createOperationalState } from '../helpers/operationalSession.js';
import { SERVICE_DESK_ROUTES, serviceDeskRouteName } from '../routeDefinitions.js';
import { contextPayload, identity, collection, ticket, detail, deferred, httpError } from './fixtures.js';
const holder = vi.hoisted(() => ({ session: null }));
vi.mock('../composables/useServiceDesk', () => ({ useServiceDesk: () => holder.session }));
import TicketFormView from '../views/TicketFormView.vue';
import Lookup from '../components/LookupSelect.vue';

// Test-only HTTP transport; application never imports these synthetic records.
const Button = { props: ['label', 'disabled', 'type'], template: '<button :type="type || \'button\'" :disabled="disabled">{{ label }}</button>' };
const Input = { props: ['modelValue', 'label', 'disabled'], emits: ['update:modelValue'], template: '<label>{{ label }}<input :value="modelValue" :disabled="disabled" @input="$emit(\'update:modelValue\', $event.target.value)" /></label>' };
const Select = { props: ['modelValue', 'options', 'disabled'], emits: ['update:modelValue'], template: '<select :value="modelValue" :disabled="disabled" @change="$emit(\'update:modelValue\', $event.target.value)"><option v-for="o in options" :key="o.value" :value="o.value">{{ o.label }}</option></select>' };
const TextArea = { props: ['modelValue', 'disabled'], emits: ['update:modelValue'], template: '<textarea :disabled="disabled" :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" />' };
let wrapper;
afterEach(() => { wrapper?.unmount(); holder.session?.operations.clear(); holder.session?.dispose(); holder.session = null; vi.unstubAllGlobals(); });
async function renderForm(writeClient) {
  vi.stubGlobal('crypto', { randomUUID: () => 'cp4-view-test-key' });
  const p = contextPayload(); p.units[0].initial_status = { id: '1', name: 'Configured initial fixture' };
  const client = { context: async () => p, list: async (_account, resource) => {
      const ids = {
        requesters: '33',
        priorities: '2',
        categories: '4',
        teams: '8',
        assignees: '7',
        queues: '6',
      };
      return collection([
        {
          id: ids[resource],
          account_id: '1',
          unit_id: '10',
          permissions: { show: true },
          name: `Fixture ${resource}`,
        },
      ]);
  } };
  const base = createServiceDeskSession(client, reactive(createSessionState()));
  const operations = createOperationalSession(writeClient, base, reactive(createOperationalState()));
  holder.session = { ...base, operations, accountId: ref('1'), userId: ref('7'), enabled: ref(true) };
  await base.start(identity);
  const router = createRouter({ history: createMemoryHistory(), routes: SERVICE_DESK_ROUTES.map(entry => ({
      path: `/app/accounts/:accountId/service-desk${entry.path ? `/${entry.path}` : ''}`,
      name: serviceDeskRouteName(entry.key),
      component: { template: '<div />' },
    })),
  });
  await router.push({ name: serviceDeskRouteName('new'), params: { accountId: '1' } }); await router.isReady();
  wrapper = mount(TicketFormView, { props: { screen: 'new' }, global: {
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
      stubs: { Button, Input, Select, TextArea, Spinner: true, Icon: true },
    },
  });
  await wrapper.findAll('select')[1].setValue('10'); await flushPromises();
  await wrapper.findAll('label').find(label => label.text().startsWith(messages.JRC_SERVICE_DESK.FIELDS.title)).find('input').setValue('Native Vue fixture');
  await wrapper.findAllComponents(Lookup).find(item => item.props('resource') === 'requesters').find('select').setValue('33');
  await wrapper.findAll('.sd-wizard-step')[1].trigger('click'); await flushPromises();
  await wrapper.findAllComponents(Lookup).find(item => item.props('resource') === 'priorities').find('select').setValue('2');
  await wrapper.findAll('.sd-wizard-step')[3].trigger('click');
  return router;
}

describe('CP4 native Vue create/readback wiring (execution pending)', () => {
  it('does not navigate or show confirmation until the persisted GET resolves', async () => {
    const read = deferred(); const create = vi.fn(async () => ({ contract_version: 1, account_id: '1', ticket_id: '20', operation: 'create', applied: true }));
    const router = await renderForm({ create, ticket: () => read.promise });
    await wrapper.find('form').trigger('submit'); await flushPromises();
    expect(create).toHaveBeenCalledTimes(1);
    expect(create.mock.calls[0][1].ticket.status_id).toBe('1');
    expect(router.currentRoute.value.name).toBe(serviceDeskRouteName('new'));
    expect(wrapper.text()).not.toContain(messages.JRC_SERVICE_DESK.OPS.STATUS.confirmed);
    read.resolve(detail(ticket({ title: 'Native Vue fixture', description: '', lock_version: 0 })));
    await flushPromises();
    expect(router.currentRoute.value.name).toBe(serviceDeskRouteName('detail'));
    expect(router.currentRoute.value.params.ticketId).toBe('20');
  });
  it('renders a backend rejection without creating an optimistic record', async () => {
    const router = await renderForm({ create: async () => { throw httpError(422); }, ticket: vi.fn() });
    await wrapper.find('form').trigger('submit'); await flushPromises();
    expect(router.currentRoute.value.name).toBe(serviceDeskRouteName('new'));
    expect(wrapper.text()).toContain(messages.JRC_SERVICE_DESK.OPS.STATUS.invalid_input);
    expect(holder.session.operations.mutation('ticket:form:write').ticket).toBeNull();
  });
});
