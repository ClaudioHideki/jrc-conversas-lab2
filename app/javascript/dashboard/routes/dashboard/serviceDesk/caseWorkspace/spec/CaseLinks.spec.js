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
vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));
import Links from '../CaseLinks.vue';
let wrapper;
beforeEach(() => {
  vi.clearAllMocks();
  holder.session = {
    state: reactive({
      status: 'ready',
      context: { account_id: '1', user_id: '2', units: [] },
    }),
  };
  holder.related.mockResolvedValue({
    contract_version: 1,
    account_id: '1',
    record_id: '20',
    unit_id: '10',
    type: 'tickets',
    items: [],
    meta: { total: 0, page: 1, per_page: 20 },
  });
});
afterEach(() => wrapper?.unmount());
async function render() {
  wrapper = mount(Links, {
    props: {
      record: {
        id: '20',
        account_id: '1',
        unit_id: '10',
        lock_version: 0,
        resource_kind: 'incident',
        permissions: { link: true },
      },
      execute: vi.fn(),
    },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: messages },
        }),
      ],
      stubs: {
        CaseDialog: {
          props: ['open'],
          template: '<section v-if="open"><slot /></section>',
        },
        Lookup: {
          props: ['modelValue'],
          emits: ['update:modelValue'],
          template:
            '<input data-requester :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" />',
        },
      },
    },
  });
  await flushPromises();
  await wrapper.find('button').trigger('click');
  await flushPromises();
}
describe('Native case ticket picker filters', () => {
  it('submits the selected requester, origin, phase and period to the scoped native endpoint', async () => {
    await render();
    await wrapper.find('[data-requester]').setValue('42');
    const selects = wrapper.findAll('select');
    await selects[0].setValue('waiting');
    await selects[1].setValue('whatsapp');
    const dates = wrapper.findAll('input[type="date"]');
    await dates[0].setValue('2026-10-01');
    await dates[1].setValue('2026-10-24');
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(holder.related).toHaveBeenLastCalledWith(
      '1',
      '20',
      expect.objectContaining({
        requester_id: '42',
        phase: 'waiting',
        source: 'whatsapp',
        created_from: '2026-10-01',
        created_to: '2026-10-24',
        linked: 'false',
        page: 1,
      }),
      expect.any(AbortSignal)
    );
    expect(wrapper.props('execute')).not.toHaveBeenCalled();
  });
  it('discards a response from another Account instead of displaying candidate data', async () => {
    holder.related.mockResolvedValue({
      contract_version: 1,
      account_id: '999',
      record_id: '20',
      unit_id: '10',
      type: 'tickets',
      items: [],
      meta: { total: 0, page: 1, per_page: 20 },
    });
    await render();
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(wrapper.props('execute')).not.toHaveBeenCalled();
  });
});
