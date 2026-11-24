import { afterEach, describe, expect, it, vi } from 'vitest';
import { reactive } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import Panel from '../ManagerialReportPanel.vue';

const mocks = vi.hoisted(() => ({
  session: null,
  units: vi.fn(),
  report: vi.fn(),
}));
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => mocks.session,
}));
vi.mock('dashboard/api/serviceDeskOperationalRules', () => ({
  default: {
    managerialReportOptions: mocks.units,
    managerialReport: mocks.report,
  },
}));

let wrapper;
afterEach(() => {
  wrapper?.unmount();
  vi.clearAllMocks();
});
const mountReport = async (allowed = true) => {
  mocks.session = {
    state: reactive({
      status: 'ready',
      context: {
        account_id: '1',
        user_id: '4',
        units: [{ id: '10' }, { id: '20' }],
        capabilities: { managerial_reports: { index: allowed } },
      },
    }),
  };
  mocks.units.mockResolvedValue({
    contract_version: 1,
    account_id: '1',
    items: [{ id: '10', name: 'Unidade autorizada' }],
  });
  const time = '2026-01-01T00:00:00-03:00';
  mocks.report.mockResolvedValue({
    contract_version: 1,
    account_id: '1',
    unit_id: '10',
    timezone: 'America/Sao_Paulo',
    meta: { page: 1, per_page: 25, total: 1 },
    items: [
      {
        id: '99',
        title: 'Chamado sintético',
        phase: 'open',
        origin: 'manual',
        opened_at: time,
        created_at: time,
        updated_at: time,
      },
    ],
  });
  wrapper = mount(Panel, {
    global: { plugins: [createI18n({ legacy: false, locale: 'pt_BR' })] },
  });
  await flushPromises();
};
const select = label =>
  wrapper
    .findAll('label')
    .find(node => node.text().startsWith(label))
    .find('select');

describe('managerial report filters', () => {
  it('shows authorized units and requests the selected origin with the opening cutoff', async () => {
    await mountReport();
    expect(
      select('Unidade')
        .findAll('option')
        .map(option => option.element.value)
    ).toEqual(['10']);
    expect(select('Origem').element.value).toBe('native');
    await select('Origem').setValue('all');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(mocks.report).toHaveBeenCalledWith(
      '1',
      '10',
      {
        from: '2026-01-01',
        date_field: 'opened_at',
        group_by: 'month',
        origin: 'all',
        page: 1,
      },
      expect.any(AbortSignal)
    );
    expect(wrapper.text()).toContain('Chamado sintético');
    expect(wrapper.text()).toContain('Criação manual');
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Limpar filtros')
      .trigger('click');
    expect(wrapper.text()).not.toContain('Chamado sintético');
    expect(select('Origem').element.value).toBe('native');
  });

  it('avoids requests without managerial access and drops results when access is revoked', async () => {
    await mountReport(false);
    expect(mocks.units).not.toHaveBeenCalled();
    expect(
      wrapper.get('button[type=submit]').attributes('disabled')
    ).toBeDefined();
    mocks.session.state.context.capabilities.managerial_reports.index = true;
    await flushPromises();
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.text()).toContain('Chamado sintético');
    mocks.session.state.context.capabilities.managerial_reports.index = false;
    await flushPromises();
    expect(wrapper.text()).not.toContain('Chamado sintético');
  });
});
