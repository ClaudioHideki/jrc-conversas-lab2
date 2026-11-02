import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
const holder = vi.hoisted(() => ({ session: null, related: vi.fn() }));
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => holder.session,
}));
vi.mock('dashboard/api/serviceDeskCases', () => ({ default: holder }));
import Communication from '../CaseExternalCommunication.vue';
let wrapper;
const row = () => ({
  id: '20',
  account_id: '1',
  unit_id: '10',
  lock_version: 0,
  ticket_ids: [],
});
const payload = items => ({
  contract_version: 1,
  account_id: '1',
  items,
  meta: { total: items.length, page: 1, per_page: 20 },
});
const render = async (record = row()) => {
  wrapper = mount(Communication, {
    props: { record, execute: vi.fn(async () => true) },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: messages },
        }),
      ],
      stubs: {
        InteractionComposer: {
          name: 'InteractionComposer',
          props: ['ticket', 'mode'],
          emits: ['updated'],
          template: '<div data-testid="native-composer" />',
        },
      },
    },
  });
  await flushPromises();
  return wrapper;
};
beforeEach(() => {
  vi.clearAllMocks();
  holder.session = {
    state: reactive({ context: { account_id: '1' } }),
    resource: () => ({ record: { id: '42', account_id: '1' } }),
    load: vi.fn(async () => {}),
    resetResource: vi.fn(),
  };
  holder.related.mockResolvedValue(payload([]));
});
afterEach(() => wrapper?.unmount());
describe('Native case external communication link refresh', () => {
  it('refreshes the linked ticket chooser after a link command updates the case version', async () => {
    await render();
    expect(wrapper.findAll('option')).toHaveLength(1);
    holder.related.mockResolvedValue(
      payload([{ id: '42', title: 'Synthetic ticket' }])
    );
    await wrapper.setProps({
      record: { ...row(), lock_version: 1, ticket_ids: ['42'] },
    });
    await flushPromises();
    expect(holder.related).toHaveBeenCalledTimes(2);
    expect(wrapper.find('option[value="42"]').text()).toContain(
      'Synthetic ticket'
    );
  });
  it('uses the existing native composer after explicit selection and records only the returned public note reference', async () => {
    holder.related.mockResolvedValue(
      payload([{ id: '42', title: 'Synthetic ticket' }])
    );
    await render({ ...row(), ticket_ids: ['42'] });
    await wrapper.find('select').setValue('42');
    await flushPromises();
    expect(holder.session.load).toHaveBeenCalledWith(
      'case:communication:20',
      'tickets',
      {},
      '42'
    );
    const native = wrapper.findComponent({ name: 'InteractionComposer' });
    expect(native.props('mode')).toBe('conversation');
    native.vm.$emit('updated', {
      account_id: '1',
      ticket_id: '42',
      result_id: '80',
    });
    await flushPromises();
    expect(wrapper.props('execute')).toHaveBeenCalledWith(
      'external_reference',
      { ticket_id: '42', note_id: '80' }
    );
  });
  it('removes a stale selected ticket when the relation is withdrawn without enabling a second sender', async () => {
    holder.related.mockResolvedValue(
      payload([{ id: '42', title: 'Synthetic ticket' }])
    );
    await render({ ...row(), ticket_ids: ['42'] });
    await wrapper.find('select').setValue('42');
    await flushPromises();
    holder.related.mockResolvedValue(payload([]));
    await wrapper.setProps({ record: { ...row(), lock_version: 1 } });
    await flushPromises();
    expect(wrapper.find('select').element.value).toBe('');
    expect(wrapper.find('[data-testid="native-composer"]').exists()).toBe(
      false
    );
    expect(wrapper.props('execute')).not.toHaveBeenCalled();
  });
  it('does not render a foreign Account response or create any publication', async () => {
    holder.related.mockResolvedValue({
      ...payload([{ id: '42', title: 'Foreign secret' }]),
      account_id: '9',
    });
    await render();
    expect(wrapper.text()).not.toContain('Foreign secret');
    expect(wrapper.props('execute')).not.toHaveBeenCalled();
  });
});
