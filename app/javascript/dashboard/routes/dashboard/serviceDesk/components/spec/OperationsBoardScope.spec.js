import { afterEach, describe, expect, it, vi } from 'vitest';
import { reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
const holder = vi.hoisted(() => ({
  session: null,
  route: null,
  board: vi.fn(),
}));
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => holder.session,
}));
vi.mock('vue-router', () => ({
  useRoute: () => holder.route,
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('dashboard/api/serviceDeskOperationsV2', () => ({
  default: { board: holder.board },
}));
import Board from '../../views/OperationsBoardView.vue';
let wrapper;
afterEach(() => {
  wrapper?.unmount();
  vi.clearAllMocks();
});
describe('Summary links preserve the authorized operations scope', () => {
  it('loads pending approvals for the linked unit and operator on the first request', async () => {
    holder.route = {
      params: { accountId: '1' },
      query: { unit_id: '10', operator_company_id: '20', status: 'pending' },
    };
    holder.session = {
      state: reactive({
        status: 'ready',
        context: {
          account_id: '1',
          capabilities: { approvals: { index: true } },
          units: [
            {
              id: '10',
              name: 'Unidade Sul',
              operator_company: { id: '20', name: 'Operadora' },
            },
          ],
        },
      }),
    };
    holder.board.mockResolvedValue({
      contract_version: 1,
      account_id: '1',
      kind: 'approvals',
      items: [],
      meta: { page: 1, per_page: 20, total: 0 },
    });
    wrapper = mount(Board, {
      props: { screen: 'approvals' },
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'pt_BR',
            messages: { pt_BR: messages },
          }),
        ],
        stubs: {
          ScopeBar: true,
          State: true,
          Panel: { template: '<section><slot /></section>' },
          Button: true,
          Pagination: true,
          NativeIncidentForm: true,
          IncidentBatchPanel: true,
        },
      },
    });
    await flushPromises();
    expect(holder.board).toHaveBeenCalledWith(
      '1',
      'approvals',
      {
        page: 1,
        per_page: 20,
        unit_id: '10',
        operator_company_id: '20',
        status: 'pending',
      },
      expect.any(AbortSignal)
    );
    expect(wrapper.get('select').element.value).toBe('pending');
  });
});
