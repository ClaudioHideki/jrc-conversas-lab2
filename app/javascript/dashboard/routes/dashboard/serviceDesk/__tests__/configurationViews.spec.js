import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { reactive, ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import { configurationContext, configurationEnvelope, configurationReceipt, configurationRow } from './configurationCases';
const holder = vi.hoisted(() => ({ session: null, list: vi.fn(), save: vi.fn(), receipt: vi.fn(), record: vi.fn() }));
vi.mock('../composables/useServiceDesk', () => ({ useServiceDesk: () => holder.session }));
vi.mock('dashboard/api/serviceDeskConfiguration', () => ({ default: holder }));
import ConfigurationManager from '../components/ConfigurationManager.vue';
const Button = { props: ['label', 'disabled', 'type'], template: '<button :type="type" :disabled="disabled">{{ label }}</button>' };
const ScopeBar = { emits: ['update:unitId'], template: '<button data-select-unit @click="$emit(\'update:unitId\', \'10\')">Select fixture unit</button>' };
const Panel = { template: '<section><slot /></section>' };
const Input = { props: ['modelValue', 'label', 'disabled'], emits: ['update:modelValue'], template: '<label>{{ label }}<input :aria-label="label" :value="modelValue" :disabled="disabled" @input="$emit(\'update:modelValue\', $event.target.value)" /></label>' };
let wrapper;
beforeEach(() => {
  [holder.list, holder.save, holder.receipt, holder.record].forEach(fn => fn.mockReset());
  holder.session = { accountId: ref('1'), state: reactive({ status: 'ready', context: configurationContext() }), revalidate: vi.fn(), retry: vi.fn() };
  holder.list.mockResolvedValue({ contract_version: 1, account_id: '1', unit_id: '10', resource: 'categories', items: [], meta: { total: 0, page: 1, per_page: 20 } });
  holder.save.mockResolvedValue(configurationEnvelope('categories', { audit_id: '80' }));
  holder.receipt.mockResolvedValue(configurationReceipt());
  holder.record.mockResolvedValue(configurationEnvelope());
});
afterEach(() => { wrapper?.unmount(); wrapper = null; });
const render = () => {
  wrapper = mount(ConfigurationManager, { props: { resource: 'categories' }, global: {
    plugins: [createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: messages } })],
    stubs: { Button, ScopeBar, Panel, Input, Select: true, Pagination: true, State: true, LookupSelect: true,
      BaseTable: { template: '<div><slot name="row" /></div>' }, BaseTableRow: Panel, BaseTableCell: Panel } } });
  return wrapper;
};
const press = label => wrapper.findAll('button').find(b => b.text() === label).trigger('click');
const startForm = async () => {
  render(); await wrapper.get('[data-select-unit]').trigger('click'); await flushPromises();
  await press(messages.JRC_SERVICE_DESK.CATALOG.new_record);
  const row = configurationRow();
  await wrapper.get(`input[aria-label="${messages.JRC_SERVICE_DESK.FIELDS.name}"]`).setValue(row.name);
  await wrapper.get(`input[aria-label="${messages.JRC_SERVICE_DESK.FIELDS.code}"]`).setValue(row.code);
  await wrapper.get('input[type="checkbox"]').setValue(true);
};
describe('CP6 catalogue UI - native Vue execution remains pending until run', () => {
  it('does not expose management or call API without affirmative backend capability', async () => {
    holder.session.state.context.capabilities.configuration.categories = false;
    render(); await flushPromises(); expect(wrapper.text()).toBe(''); expect(holder.list).not.toHaveBeenCalled();
  });
  it('requires explicit unit selection; an empty management result is not invented', async () => {
    render(); await flushPromises(); expect(holder.list).not.toHaveBeenCalled();
    await wrapper.get('[data-select-unit]').trigger('click'); await flushPromises(); expect(holder.list).toHaveBeenCalledOnce();
    expect(holder.save).not.toHaveBeenCalled();
  });
  it('confirms only after POST, audit receipt and independent GET match', async () => {
    await startForm(); await wrapper.findAll('form')[1].trigger('submit'); await flushPromises();
    expect(holder.save).toHaveBeenCalledOnce(); expect(holder.receipt).toHaveBeenCalledOnce(); expect(holder.record).toHaveBeenCalledOnce();
    expect(wrapper.text()).toContain(messages.JRC_SERVICE_DESK.ADMIN.feedback.confirmed);
    expect(holder.session.revalidate).toHaveBeenCalledOnce();
  });
  it('keeps readback pending if the independent GET fails; never reports a fake success', async () => {
    holder.record.mockRejectedValue(new Error('Test unavailable transport'));
    await startForm(); await wrapper.findAll('form')[1].trigger('submit'); await flushPromises();
    expect(wrapper.text()).toContain(messages.JRC_SERVICE_DESK.ADMIN.feedback.readback_pending);
    expect(wrapper.text()).not.toContain(messages.JRC_SERVICE_DESK.ADMIN.feedback.confirmed);
    expect(holder.session.revalidate).not.toHaveBeenCalled();
  });
  it('clears records when Account authorization is removed', async () => {
    holder.list.mockResolvedValue({ contract_version: 1, account_id: '1', unit_id: '10', resource: 'categories', items: [configurationRow()], meta: { total: 1, page: 1, per_page: 20 } });
    render(); await wrapper.get('[data-select-unit]').trigger('click'); await flushPromises();
    expect(wrapper.text()).toContain('Fixture catalogue'); holder.session.state.context = null; holder.session.state.status = 'denied';
    await flushPromises(); expect(wrapper.text()).not.toContain('Fixture catalogue');
  });
});
