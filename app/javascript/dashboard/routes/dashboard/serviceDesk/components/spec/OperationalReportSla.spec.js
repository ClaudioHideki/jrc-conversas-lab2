import { afterEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
const mocks = vi.hoisted(() => ({ report: vi.fn(), scope: null }));
vi.mock('dashboard/api/serviceDeskOperationalRules', () => ({
  default: { report: (...args) => mocks.report(...args) },
}));
vi.mock('../../composables/useOperationalScope', () => ({
  useOperationalScope: () => mocks.scope,
}));
vi.mock('dashboard/routes/dashboard/jrcCustomers/useCustomerMaster', () => ({
  useCustomerMaster: () => ({ canAccess: ref(false) }),
}));
import Report from '../OperationalReportPanel.vue';
let wrapper;
afterEach(() => {
  wrapper?.unmount();
  vi.clearAllMocks();
});
describe('report SLA coverage and completed-clock denominator', () => {
  it.each([false, true])(
    'does not present unmeasured or unfinished clocks as zero violations; completed=%s',
    async completed => {
      const context = {
        account_id: '1',
        units: [{ id: '10' }],
        effective_permissions: ['jrc_service_desk_sla_view'],
        capabilities: { operational_reports: { index: true } },
      };
      mocks.scope = {
        allowed: ref(true),
        identity: ref('1:10'),
        session: { state: { context } },
        begin: () => ({ context, unit: '10' }),
        live: () => true,
        cancel: vi.fn(),
      };
      const row = {
        observed: completed ? 1 : 0,
        completed: completed ? 1 : 0,
        completed_breached: 0,
        running_overdue: 0,
        mean_elapsed_seconds: completed ? 12 : null,
      };
      mocks.report.mockResolvedValue({
        contract_version: 1,
        account_id: '1',
        unit_id: '10',
        items: [],
        meta: { page: 1, per_page: 25, total: 0 },
        report: {
          cohort: 'authorized_tickets_opened_in_half_open_period',
          observed_at: '2026-10-23T12:00:00Z',
          total: 0,
          ...Object.fromEntries(
            [
              'by_unit',
              'by_service',
              'by_origin',
              'by_category',
              'by_priority',
            ].map(key => [key, { items: [], truncated: false }])
          ),
          by_customer: null,
          by_channel: null,
          reopen: null,
          fcr: { value: null },
          quality: { value: null },
          sla: {
            first_response: row,
            resolution: {
              ...row,
              observed: 2,
              completed: 0,
              completed_breached: 0,
              mean_elapsed_seconds: null,
            },
            attendance: {
              ...row,
              observed: 0,
              completed: 0,
              completed_breached: 0,
              mean_elapsed_seconds: null,
            },
          },
        },
      });
      wrapper = mount(Report, {
        global: {
          plugins: [
            createI18n({
              legacy: false,
              locale: 'pt_BR',
              messages: { pt_BR: messages },
            }),
          ],
          stubs: {
            Panel: { template: '<section><slot /></section>' },
            ScopeBar: true,
            LookupSelect: true,
            ServiceSelect: true,
            CompanyPicker: true,
            TicketTable: true,
            Pagination: true,
            Button: {
              props: ['label', 'type', 'disabled'],
              template:
                '<button :type="type || \'button\'" :disabled="disabled">{{ label }}</button>',
            },
          },
        },
      });
      await wrapper.find('form').trigger('submit');
      await flushPromises();
      expect(mocks.report).toHaveBeenCalledOnce();
      const rows = wrapper
        .findAll('tbody tr')
        .map(tr => tr.findAll('td').map(td => td.text()));
      const unavailable = messages.JRC_SERVICE_DESK.COMPLETION.not_available;
      expect(rows[0].slice(1)).toEqual(
        completed ? ['1', '1', '12', '0'] : ['0', '0', unavailable, unavailable]
      );
      expect(rows[1].slice(1)).toEqual(['0', '0', unavailable, unavailable]);
      expect(rows[2].slice(1)).toEqual(['2', '0', unavailable, unavailable]);
      expect(wrapper.find('caption').text()).toContain(
        'apenas relógios concluídos'
      );
    }
  );
});
