import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
const mocks = vi.hoisted(() => ({
  session: null,
  list: vi.fn(),
  create: vi.fn(),
  download: vi.fn(),
  report: vi.fn(),
  export: vi.fn(),
}));
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => mocks.session,
}));
vi.mock('dashboard/api/serviceDeskReportExports', () => ({ default: mocks }));
vi.mock('dashboard/api/serviceDeskSatisfaction', () => ({ default: mocks }));
vi.mock('../../../jrcCustomers/useCustomerMaster', () => ({
  useCustomerMaster: () => ({ canAccess: false }),
}));
import ReportExportMenu from '../ReportExportMenu.vue';
import SatisfactionDashboard from '../SatisfactionDashboard.vue';
import SavedReportQueries from '../SavedReportQueries.vue';
let wrapper;
const plugins = () => [
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: messages } }),
];
const envelope = extra => ({
  contract_version: 1,
  account_id: '1',
  unit_id: '10',
  ...extra,
});
beforeEach(() => {
  vi.clearAllMocks();
  mocks.session = {
    state: reactive({
      status: 'ready',
      context: {
        account_id: '1',
        user_id: '7',
        units: [{ id: '10' }],
        capabilities: {
          operational_reports: { index: true, export: true },
          surveys: { index: true, export: true },
        },
      },
    }),
  };
  mocks.list.mockResolvedValue(envelope({ items: [] }));
  localStorage.clear();
});
afterEach(() => {
  wrapper?.unmount();
  vi.useRealTimers();
});

describe('processed report files', () => {
  it('submits only the applied filters and reconciled count, exposes formats and enforces the advertised limit', async () => {
    mocks.create.mockResolvedValue(
      envelope({ id: '50', format: 'csv_detailed', state: 'queued' })
    );
    wrapper = mount(ReportExportMenu, {
      props: {
        unitId: '10',
        filters: { priority_id: '3' },
        total: 2,
        limits: { xlsx: 1 },
      },
      global: { plugins: plugins() },
    });
    await flushPromises();
    wrapper.vm.openMenu();
    await flushPromises();
    const buttons = wrapper.findAll('button');
    expect(
      buttons
        .find(button => button.text().includes('Excel completo'))
        .attributes('disabled')
    ).toBeDefined();
    await buttons
      .find(button => button.text().includes('CSV detalhado'))
      .trigger('click');
    await flushPromises();
    expect(mocks.create).toHaveBeenCalledWith(
      '1',
      {
        format: 'csv_detailed',
        expected_count: 2,
        filters: { unit_id: '10', priority_id: '3' },
      },
      expect.any(AbortSignal)
    );
    expect(wrapper.text()).toContain('Na fila');
    expect(wrapper.text()).toContain('Nenhum envio automático');
  });

  it('clears an export on grant revocation and rejects a foreign-account API response', async () => {
    mocks.list.mockResolvedValue(
      envelope({
        items: [
          envelope({
            id: '50',
            format: 'xlsx',
            state: 'ready',
            filename: 'ready.xlsx',
          }),
        ],
      })
    );
    wrapper = mount(ReportExportMenu, {
      props: { unitId: '10', filters: {}, total: 1 },
      global: { plugins: plugins() },
    });
    await flushPromises();
    wrapper.vm.openMenu();
    await flushPromises();
    expect(wrapper.text()).toContain('ready.xlsx');
    mocks.session.state.context.capabilities.operational_reports.export = false;
    await flushPromises();
    expect(wrapper.text()).not.toContain('ready.xlsx');
    expect(mocks.download).not.toHaveBeenCalled();
  });

  it('keeps saved criteria separate for each native account/user and rejects unknown stored filters', async () => {
    localStorage.setItem(
      'jrc-report-queries:v1:2:7',
      JSON.stringify([{ name: 'Foreign criteria', unit_id: '10', filters: {} }])
    );
    wrapper = mount(SavedReportQueries, {
      props: { unitId: '10', filters: { service_id: '2' } },
      global: { plugins: plugins() },
    });
    await wrapper.find('button').trigger('click');
    expect(wrapper.text()).not.toContain('Foreign criteria');
    await wrapper.find('input').setValue('Minha consulta');
    await wrapper.find('form').trigger('submit');
    expect(
      JSON.parse(localStorage.getItem('jrc-report-queries:v1:1:7'))[0]
    ).toEqual({
      name: 'Minha consulta',
      unit_id: '10',
      filters: { service_id: '2' },
    });
  });
});

describe('satisfaction sources', () => {
  it('renders signed NPS and measured CSAT while preserving missing delivery evidence', async () => {
    mocks.report.mockResolvedValue(
      envelope({
        timezone: 'UTC',
        meta: { total: 0 },
        items: [],
        services: [],
        distribution: [1, 2, 3, 4, 5].map(score => ({
          score,
          count: score === 5 ? 1 : 0,
        })),
        summary: {
          response_count: 1,
          csat: 4.5,
          nps: -20,
          trend: [
            {
              day: '2026-11-12',
              kind: 'csat',
              response_count: 1,
              average_score: 4.5,
            },
          ],
          delivery: { available: false },
        },
      })
    );
    wrapper = mount(SatisfactionDashboard, {
      props: { unitId: '10' },
      global: {
        plugins: plugins(),
        stubs: { ServiceSelect: true, CompanyPicker: true, ReportDialog: true },
      },
    });
    await wrapper.find('form').trigger('submit');
    await flushPromises();
    expect(wrapper.text()).toContain('-20,0');
    expect(wrapper.text()).toContain('4,5 / 5');
    expect(wrapper.findAll('article')[0].text()).toContain('—');
    expect(wrapper.find('polyline').attributes('points')).toBe('25,41.25');
    expect(mocks.report).toHaveBeenCalledWith(
      '1',
      { unit_id: '10', period_basis: 'cohort' },
      expect.any(AbortSignal)
    );
    mocks.session.state.context.capabilities.surveys.index = false;
    await flushPromises();
    expect(wrapper.text()).not.toContain('4,5 / 5');
  });
});
