import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import messages from 'dashboard/i18n/locale/pt_BR/jrcOperator.json';
import OperatorPage from '../OperatorPage.vue';
const state = vi.hoisted(() => ({ route: null, api: null, client: vi.fn() }));
vi.mock('vue-router', () => ({ useRoute: () => state.route }));
vi.mock('dashboard/api/jrcOperator', () => ({ operatorClient: (...args) => state.client(...args) }));
beforeEach(() => {
 state.route = reactive({ params: { accountId: '8' } });
 state.api = { context: vi.fn().mockResolvedValue({ enabled: true, capabilities: ['read', 'reserve', 'prepare_boleto'] }),
  bindings: vi.fn().mockResolvedValue([{ id: 1, company: 'Synthetic issuer', contact: 'Synthetic customer' }]),
  read: vi.fn().mockImplementation((id, action) => Promise.resolve(action === 'options' ? { ddds: [], orders: [], conversations: [] } : action === 'customer' ? { name: 'Synthetic customer' } : [])),
  post: vi.fn(), pdf: vi.fn() };
 state.client.mockReset().mockReturnValue(state.api);
});
const render = () => mount(OperatorPage, { global: { plugins: [createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: messages } })] } });
it('does not query external projections when access is disabled', async () => {
 state.api.context.mockResolvedValue({ enabled: false, capabilities: [] });
 const wrapper = render(); await flushPromises();
 expect(wrapper.text()).toContain('Indisponível'); expect(state.api.bindings).not.toHaveBeenCalled(); expect(state.api.read).not.toHaveBeenCalled();
});
it('loads the selected customer and keeps financial authority explicit', async () => {
 const wrapper = render(); await flushPromises(); await wrapper.find('select').setValue('1'); await flushPromises();
 await wrapper.findAll('button').find(b => b.text() === 'Cliente').trigger('click'); await flushPromises();
 expect(state.api.read).toHaveBeenCalledWith(1, 'customer', undefined, expect.anything());
 expect(wrapper.text()).toContain('Synthetic customer'); expect(wrapper.text()).toContain('Bem Te Vi controla faturas e baixas oficiais');
});
it('does not offer retrieval for unknown or paid charges', async () => {
 state.api.read.mockImplementation((id, action) => Promise.resolve(action === 'options' ? { ddds: [], orders: [], conversations: [] } : { items: [{ id: '44', official_status: 'unknown' }, { id: '45', official_status: 'paid' }] }));
 const wrapper = render(); await flushPromises(); await wrapper.find('select').setValue('1'); await flushPromises();
 await wrapper.findAll('button').find(b => b.text() === 'Cobranças').trigger('click'); await flushPromises();
 const buttons = wrapper.findAll('button').filter(b => b.text() === 'Obter PDF');
 expect(buttons).toHaveLength(2); expect(buttons.every(b => b.attributes('disabled') !== undefined)).toBe(true);
});
it('does not show reservation actions for readers', async () => {
 state.api.context.mockResolvedValue({ enabled: true, capabilities: ['read'] });
 const wrapper = render(); await flushPromises(); await wrapper.find('select').setValue('1'); await flushPromises();
 expect(wrapper.text()).not.toContain('Motivo da reserva'); expect(state.api.post).not.toHaveBeenCalled();
});
it('ignores a late context from another account', async () => {
 let resolve; state.api.context.mockReturnValue(new Promise(r => { resolve = r; }));
 const wrapper = render(); await flushPromises();
 const next = { ...state.api, context: vi.fn().mockResolvedValue({ enabled: false, capabilities: [] }) };
 state.client.mockReturnValue(next); state.route.params.accountId = '9'; await flushPromises();
 resolve({ enabled: true, capabilities: ['read'] }); await flushPromises();
 expect(wrapper.text()).toContain('Indisponível'); expect(state.api.bindings).not.toHaveBeenCalled();
});
it('keeps the current account busy when an older customer request finishes', async () => {
 let resolveOld; let resolveNew;
 const options = { ddds: [], orders: [], conversations: [] };
 state.api.read.mockImplementation((id, action) => action === 'options' ? Promise.resolve(options) : new Promise(r => { resolveOld = r; }));
 const wrapper = render(); await flushPromises(); await wrapper.find('select').setValue('1'); await flushPromises();
 const customerButton = () => wrapper.findAll('button').find(b => b.text() === 'Cliente');
 await customerButton().trigger('click');
 const next = { ...state.api, context: vi.fn().mockResolvedValue({ enabled: true, capabilities: ['read'] }),
  read: vi.fn().mockImplementation((id, action) => action === 'options' ? Promise.resolve(options) : new Promise(r => { resolveNew = r; })) };
 state.client.mockReturnValue(next); state.route.params.accountId = '9'; await flushPromises();
 await wrapper.find('select').setValue('1'); await flushPromises(); await customerButton().trigger('click');
 resolveOld({ name: 'Customer from old account' }); await flushPromises();
 expect(customerButton().attributes('disabled')).toBeDefined(); expect(wrapper.text()).not.toContain('Customer from old account');
 resolveNew({ name: 'Current customer' }); await flushPromises();
 expect(wrapper.text()).toContain('Current customer'); expect(customerButton().attributes('disabled')).toBeUndefined();
});
it('does not offer a second release for a reservation already released', async () => {
 state.api.context.mockResolvedValue({ enabled: true, capabilities: ['read', 'release'] });
 state.api.read.mockImplementation((id, action) => Promise.resolve(action === 'options' ? { ddds: [], orders: [], conversations: [] } : [
  { id: 1, kind: 'reserve', state: 'confirmed', result: { reservation_id: 'synthetic-reservation' } },
  { id: 2, kind: 'release', state: 'confirmed', result: { reservation_id: 'synthetic-reservation' } },
 ]));
 const wrapper = render(); await flushPromises(); await wrapper.find('select').setValue('1'); await flushPromises();
 await wrapper.findAll('button').find(b => b.text() === 'Atualizar').trigger('click'); await flushPromises();
 expect(wrapper.findAll('button').filter(b => b.text() === 'Liberar')).toHaveLength(0);
});
