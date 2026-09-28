import { afterEach, beforeEach, describe, it, expect, vi } from 'vitest';
import { reactive, ref, defineComponent } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createRouter, createMemoryHistory } from 'vue-router';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import { decodeContext, decodeTicket } from '../helpers/contracts.js';
import { contextPayload, identity, ticket, detail, deferred, httpError } from './fixtures.js';
const holder = vi.hoisted(() => ({ session: null, context: vi.fn(), customer: vi.fn(), conversation: vi.fn() }));
vi.mock('../composables/useServiceDesk', () => ({ useServiceDesk: () => holder.session }));
vi.mock('dashboard/api/serviceDesk', () => ({ default: { context: holder.context } }));
vi.mock('dashboard/api/serviceDeskNative', () => ({ default: { customer: holder.customer, conversation: holder.conversation } }));
import CustomerContextPanel from '../components/CustomerContextPanel.vue';
import TicketOperations from '../components/TicketOperations.vue';
import AccessStateView from '../views/AccessStateView.vue';
import { useServiceDeskNavigation } from 'dashboard/composables/useServiceDeskNavigation';
const Button = { props: ['label', 'disabled'], template: '<button :disabled="disabled">{{ label }}</button>' };
const i18n = () => createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: messages } });
let wrappers = [];
const record = flags => decodeTicket(detail(ticket({ permissions: { show: true, ...flags } })), holder.session.state.context, '20');
const customerPayload = () => ({ contract_version: 1, account_id: '1', unit_id: '10', ticket_id: '20', contact: { id: '33', account_id: '1', name: 'Fixture original contact' }, company: null, company_state: 'not_linked' });
const render = (component, props = {}, plugins = []) => {
  const wrapper = mount(component, { props, global: { plugins: [i18n(), ...plugins], stubs: { Button, Icon: true, Spinner: true, Lookup: true, Select: true, Pagination: true } } }); wrappers.push(wrapper); return wrapper;
};
beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setInterval', 'clearInterval'] }); holder.context.mockReset(); holder.customer.mockReset(); holder.conversation.mockReset();
  holder.context.mockResolvedValue(contextPayload()); holder.customer.mockResolvedValue(customerPayload());
  const state = reactive({ status: 'ready', context: decodeContext(contextPayload(), identity) });
  holder.session = { state, accountId: ref('1'), userId: ref('7'), dispose: () => { state.status = 'idle'; state.context = null; },
    operations: { state: reactive({ revision: 0 }), cancel: vi.fn(), read: vi.fn(), mutation: () => ({ status: 'idle' }), resource: () => ({ status: 'idle', data: null }) } };
});
afterEach(() => { wrappers.forEach(w => w.unmount()); wrappers = []; vi.useRealTimers(); });
describe('CP5 native Vue integration (execution requires project runtime)', () => {
  it('does not fetch native customer data without the backend capability', async () => {
    render(CustomerContextPanel, { ticket: record({ view_customer: false }) }); await flushPromises(); expect(holder.customer).not.toHaveBeenCalled();
  });
  it('projects the original Contact without copying it or showing operator-company data', async () => {
    const wrapper = render(CustomerContextPanel, { ticket: record({ view_customer: true }) }); await flushPromises();
    expect(wrapper.text()).toContain('Fixture original contact'); expect(holder.customer).toHaveBeenCalledTimes(1);
  });
  it('clears a stale customer response after Account context is removed', async () => {
    const wait = deferred(); holder.customer.mockReturnValue(wait.promise);
    const wrapper = render(CustomerContextPanel, { ticket: record({ view_customer: true }) });
    holder.session.dispose(); await flushPromises(); wait.resolve(customerPayload()); await flushPromises();
    expect(wrapper.text()).not.toContain('Fixture original contact');
  });
  it('renders genuine denied/not-found instead of successful empty customer data', async () => {
    holder.customer.mockRejectedValue(httpError(404));
    const wrapper = render(CustomerContextPanel, { ticket: record({ view_customer: true }) }); await flushPromises();
    expect(wrapper.text()).toContain(messages.JRC_SERVICE_DESK.STATES.not_found);
    expect(wrapper.text()).not.toContain('Fixture original contact');
  });
  it('renders transfer and priority actions independently from assignment/data-edit', async () => {
    const wrapper = render(TicketOperations, { ticket: record({ transfer: true, change_priority: true, update: false, assign: false }) });
    expect(wrapper.text()).toContain(messages.JRC_SERVICE_DESK.NATIVE.transfer);
    expect(wrapper.text()).toContain(messages.JRC_SERVICE_DESK.NATIVE.change_priority);
    expect(wrapper.text()).not.toContain(messages.JRC_SERVICE_DESK.OPS.assignment);
  });
  it('hides the native sidebar entry until the backend has explicitly authorized it', async () => {
    const wait = deferred(); holder.context.mockReturnValue(wait.promise);
    const Harness = defineComponent({ setup() { return { access: useServiceDeskNavigation(ref('1'), ref('7'), ref(true)) }; }, template: '<span v-if="access.visible">Service Desk link</span>' });
    const wrapper = render(Harness); expect(wrapper.text()).not.toContain('Service Desk link');
    wait.resolve(contextPayload()); await flushPromises(); expect(wrapper.text()).toContain('Service Desk link');
  });
  it('stops showing sidebar access after a server-side membership revocation', async () => {
    const Harness = defineComponent({ setup() { return { access: useServiceDeskNavigation(ref('1'), ref('7'), ref(true)) }; }, template: '<span v-if="access.visible">Service Desk link</span>' });
    const wrapper = render(Harness); await flushPromises(); expect(wrapper.text()).toContain('Service Desk link');
    holder.context.mockRejectedValue(httpError(403)); window.dispatchEvent(new Event('focus')); await flushPromises();
    expect(wrapper.text()).not.toContain('Service Desk link');
  });
  it('flag disabled causes no operational context request', async () => {
    const Harness = defineComponent({ setup() { return { access: useServiceDeskNavigation(ref('1'), ref('7'), ref(false)) }; }, template: '<span v-if="access.visible">Service Desk link</span>' });
    render(Harness); await flushPromises(); expect(holder.context).not.toHaveBeenCalled();
  });
  it('the data-free denial screen returns to native Account home without any extra login', async () => {
    const router = createRouter({ history: createMemoryHistory(), routes: [
      { path: '/app/accounts/:accountId/dashboard', name: 'home', component: { template: '<div />' } },
      { path: '/app/accounts/:accountId/service-desk-access', name: 'jrc_service_desk_denied', component: AccessStateView },
    ] });
    await router.push({ name: 'jrc_service_desk_denied', params: { accountId: '1' }, query: { reason: 'denied' } });
    const wrapper = render(AccessStateView, {}, [router]); await wrapper.find('button').trigger('click'); await flushPromises();
    expect(router.currentRoute.value.name).toBe('home'); expect(holder.context).not.toHaveBeenCalled();
  });
});
