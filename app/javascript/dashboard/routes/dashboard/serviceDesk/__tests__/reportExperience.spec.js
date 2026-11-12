import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { computed, defineComponent, reactive } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createRouter, createMemoryHistory } from 'vue-router';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import ReportCenter from '../components/ReportCenter.vue';
import ReportsView from '../views/ReportsView.vue';
import { csvText } from '../helpers/csvExport';
import { contextPayload } from './fixtures';
const mocks = vi.hoisted(() => ({ session: null, export: vi.fn() }));
vi.mock('../composables/useServiceDesk', () => ({
  useServiceDesk: () => mocks.session,
}));
vi.mock('../composables/useSupervisionReport.js', () => ({
  useSupervisionReport: () => ({ status: 'idle', result: null, load: vi.fn() }),
}));
vi.mock('../components/OperationalReportPanel.vue', () => ({
  default: defineComponent({
    setup(_, { expose }) {
      expose({ canExport: computed(() => true), exportCsv: mocks.export });
      return {};
    },
    template: '<section data-report-data>Authorized report</section>',
  }),
}));
let wrapper;
beforeEach(() => {
  mocks.session = {
    state: reactive({
      status: 'ready',
      context: contextPayload({
        capabilities: Object.fromEntries(
          [
            'reports',
            'operational_reports',
            'dashboard',
            'sla',
            'assets',
            'tasks',
            'assignees',
            'contracts',
          ].map(key => [key, { index: true }])
        ),
      }),
    }),
  };
  HTMLDialogElement.prototype.showModal = function showModal() {
    this.setAttribute('open', '');
  };
});
afterEach(() => {
  wrapper?.unmount();
  vi.clearAllMocks();
});
const render = async (component = ReportCenter) => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/reports', name: 'reports', component: { template: '<div />' } },
    ],
  });
  await router.push('/reports');
  wrapper = mount(component, {
    global: {
      plugins: [
        router,
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: messages },
        }),
      ],
      stubs: {
        Button: { props: ['label'], template: '<button>{{ label }}</button>' },
        LiveKpis: true,
      },
    },
  });
  await flushPromises();
  return router;
};
const click = async label => {
  await wrapper
    .findAll('button')
    .find(button => button.text() === label)
    .trigger('click');
  await flushPromises();
};
describe('Report windows and exports preserve the current workspace', () => {
  it('keeps every report category in the same card layout and emits a query instead of navigating away', async () => {
    const router = await render();
    await click('Executivo');
    expect(wrapper.findAll('article')).toHaveLength(2);
    await click('Resumo por empresa');
    expect(wrapper.emitted('select')[0][0]).toEqual({
      target: 'operational',
      title: 'Resumo por empresa',
      dimension: 'by_customer',
    });
    expect(router.currentRoute.value.path).toBe('/reports');
    await click('Patrimônio');
    expect(wrapper.findAll('article')).toHaveLength(1);
    expect(wrapper.text()).toContain('Relação de patrimônio');
    await click('Exportações');
    expect(wrapper.text()).toContain('Exportar solicitações em CSV');
  });
  it('opens a native dialog, exports its authorized data, closes with Escape, and retains the selected library tab', async () => {
    const router = await render(ReportsView);
    await click('Executivo');
    await click('Resumo por empresa');
    expect(wrapper.find('dialog').attributes('open')).toBe('');
    expect(wrapper.find('[data-report-data]').exists()).toBe(true);
    await click(messages.JRC_SERVICE_DESK.REPORT_EXPERIENCE.export_view);
    expect(mocks.export).toHaveBeenCalledTimes(1);
    await wrapper.find('dialog').trigger('cancel');
    expect(wrapper.find('dialog').exists()).toBe(false);
    expect(wrapper.findAll('article')).toHaveLength(2);
    expect(router.currentRoute.value.path).toBe('/reports');
  });
  it('does not expose a report or export after its capability is revoked', async () => {
    await render(ReportsView);
    await click('Relatório operacional detalhado');
    mocks.session.state.context = contextPayload({ capabilities: {} });
    await flushPromises();
    expect(wrapper.find('dialog').exists()).toBe(false);
    expect(wrapper.findAll('article')).toHaveLength(0);
    expect(mocks.export).not.toHaveBeenCalled();
  });
  it('exports quoted UTF-8 cells and neutralizes spreadsheet formulas and control prefixes', () => {
    const csv = csvText([
      ['Nome', 'Valor'],
      ['Ação, "teste"', '=HYPERLINK("test")'],
      ['linha\nseguinte', '\tformula'],
      ['Nulo', null],
    ]);
    expect(csv).toContain('"Ação, ""teste"""');
    expect(csv).toContain(`"'=HYPERLINK`);
    expect(csv).toContain(`"'\tformula"`);
    expect(csv.startsWith('\uFEFF')).toBe(true);
    expect(csv.endsWith('\r\n')).toBe(true);
  });
});
