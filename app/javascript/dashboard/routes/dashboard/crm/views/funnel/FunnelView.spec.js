import { config, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { routeLocationKey, routerKey } from 'vue-router';
import { createStore } from 'vuex';
import FunnelAPI from 'dashboard/api/crm/funnel';
import ptBR from 'dashboard/i18n/locale/pt_BR/crm.json';
import FunnelView from './FunnelView.vue';

vi.mock('dashboard/api/crm/funnel', () => ({
  default: { show: vi.fn() },
}));

it('renders the sales funnel and Brazilian formats with the dashboard locale pt_BR', async () => {
  const originalPlugins = config.global.plugins;
  const i18n = createI18n({
    legacy: false,
    locale: 'pt_BR',
    messages: { pt_BR: ptBR },
  });
  FunnelAPI.show.mockResolvedValueOnce({
    data: {
      pipelines: [{ id: 1, name: 'Comercial' }],
      stages: [{ id: 1, name: 'Ganho', active: true, is_won: true }],
      owners: [],
      teams: [],
      pipeline_id: 1,
      month: '2026-11',
      as_of: '2026-11-28T12:00:00Z',
      timezone: 'America/Sao_Paulo',
      deals: [
        {
          id: 1,
          title: 'Negócio de teste',
          owner_id: 1,
          owner_name: 'Pessoa de teste',
          stage_id: 1,
          status: 'won',
          currency: 'BRL',
          value_cents: 123450,
          created_at: '2026-11-10T12:00:00Z',
          won_at: '2026-11-15T12:00:00Z',
          updated_at: '2026-11-15T12:00:00Z',
          moves: [],
        },
      ],
    },
  });
  config.global.plugins = [i18n];
  let wrapper;
  try {
    wrapper = mount(FunnelView, {
      global: {
        plugins: [createStore({})],
        provide: {
          [routeLocationKey]: { params: { accountId: '1' }, query: {} },
          [routerKey]: { replace: vi.fn() },
        },
      },
    });
    await flushPromises();

    expect(wrapper.text()).toContain('Conversão por etapa');
    expect(wrapper.text()).toContain('R$');
    expect(wrapper.text()).toContain('1.234,50');
    expect(wrapper.text()).toContain('5 dias');
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  } finally {
    wrapper?.unmount();
    config.global.plugins = originalPlugins;
  }
});
