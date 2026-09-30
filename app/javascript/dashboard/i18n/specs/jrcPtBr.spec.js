import { createI18n } from 'vue-i18n';
import { config, mount } from '@vue/test-utils';
import { ref } from 'vue';
import en from '../locale/en';
import ptBR from '../locale/pt_BR';
import projectsEn from '../../routes/dashboard/jrcProjects/en.json';
import projectsPt from '../locale/pt_BR/jrcProjects.json';
import agendaEn from '../../routes/dashboard/jrcOperations/en.json';
import agendaPt from '../locale/pt_BR/jrcOperations.json';
import { useProjects } from '../../routes/dashboard/jrcProjects/useProjects';
import { useAgenda } from '../../routes/dashboard/jrcOperations/useAgenda';
import CrmStatusBadge from '../../routes/dashboard/crm/components/shared/CrmStatusBadge.vue';
import { useCommercialLabels } from '../../routes/dashboard/crm/composables/useCommercialLabels';

vi.mock('../../routes/dashboard/jrcOperations/useOperations', () => ({
  useOperations: () => ({ accountId: ref('1'), status: ref({}) }),
}));

const leaves = (object, prefix = '') =>
  Object.entries(object).flatMap(([key, value]) =>
    typeof value === 'object'
      ? leaves(value, `${prefix}${key}.`)
      : [[`${prefix}${key}`, value]]
  );
const parameters = text =>
  [...text.matchAll(/\{(\w+)\}/g)].map(x => x[1]).sort();

describe('JRC pt-BR catalogs and display labels', () => {
  const originalPlugins = config.global.plugins;
  let i18n;
  beforeEach(() => {
    i18n = createI18n({
      legacy: false,
      locale: 'pt_BR',
      fallbackLocale: 'en',
      messages: { en, pt_BR: ptBR },
    });
    config.global.plugins = [i18n];
  });
  afterEach(() => {
    config.global.plugins = originalPlugins;
  });

  it.each([
    'CRM',
    'JRC_NICO',
    'JRC_SERVICE_DESK',
    'CALLS_PAGE',
    'SOFTPHONE',
    'JRC_HOME',
  ])(
    'registers all %s messages in pt-BR without falling back to English',
    namespace => {
      const translated = Object.fromEntries(leaves(ptBR[namespace]));
      leaves(en[namespace]).forEach(([key, value]) => {
        expect(translated[key], `${namespace}.${key}`).toBeTypeOf('string');
        expect(parameters(translated[key]), key).toEqual(parameters(value));
        expect(i18n.global.te(`${namespace}.${key}`, 'pt_BR')).toBe(true);
      });
    }
  );

  it.each([
    [projectsEn, projectsPt],
    [agendaEn, agendaPt],
  ])(
    'preserves message keys and interpolation in the local catalogs',
    (english, portuguese) => {
      expect(Object.keys(portuguese).sort()).toEqual(
        Object.keys(english).sort()
      );
      Object.entries(english).forEach(([key, value]) => {
        expect(parameters(portuguese[key]), key).toEqual(parameters(value));
      });
    }
  );

  it('translates contact, CRM navigation, access and calling controls', () => {
    expect(i18n.global.t('CRM.CONTACT_LEAD.CENTER_TITLE')).toBe(
      'Central de relacionamento'
    );
    expect(i18n.global.t('CRM.NAVIGATION.NEXT')).toBe('Próximas abas do CRM');
    expect(i18n.global.t('CRM.TEAM_METRICS.REVENUE')).toBe('Receita ganha');
    expect(i18n.global.t('JRC_SERVICE_DESK.UNIT_ACCESS.grant')).toBe(
      'Conceder acesso'
    );
    expect(i18n.global.t('SOFTPHONE.ENABLE_NOTIFICATIONS')).toBe(
      'Ativar notificações de chamadas'
    );
    expect(
      i18n.global.t('JRC_SERVICE_DESK.UNIT_ACCESS.pagination', {
        page: 2,
        pages: 3,
        total: 51,
      })
    ).toBe('Página 2 de 3 · 51 registros');
  });

  it('translates both project permission lists without changing identifiers', () => {
    [ptBR.CUSTOM_ROLE.PERMISSIONS, ptBR.CUSTOM_ROLE.FORM.PERMISSIONS].forEach(
      section => {
        Object.keys(en.CUSTOM_ROLE.PERMISSIONS)
          .filter(key => key.startsWith('JRC_PROJECTS_'))
          .forEach(key => expect(section[key], key).toMatch(/^Projetos: /));
      }
    );
  });

  it('uses the project catalog in a mounted component and reacts to locale changes', async () => {
    const wrapper = mount({
      setup: useProjects,
      template: '<p>{{ projectText("EVENT_TASK_CREATED") }}</p>',
    });
    expect(wrapper.text()).toBe('Tarefa criada');
    i18n.global.locale.value = 'en';
    await wrapper.vm.$nextTick();
    expect(wrapper.text()).toBe('Task created');
    wrapper.unmount();
  });

  it('uses the agenda catalog for filters and empty state', () => {
    const wrapper = mount({
      setup: useAgenda,
      template:
        '<p>{{ agendaText("IN_PROGRESS") }} · {{ agendaText("EMPTY") }}</p>',
    });
    expect(wrapper.text()).toContain('Em andamento');
    expect(wrapper.text()).toContain(agendaPt.EMPTY);
    wrapper.unmount();
  });

  it.each([
    ['open', 'Aberto'],
    ['won', 'Ganho'],
    ['lost', 'Perdido'],
    ['awaiting_signature', 'Aguardando assinatura'],
  ])(
    'renders %s in Portuguese without changing its value or badge color',
    (value, label) => {
      const wrapper = mount(CrmStatusBadge, { props: { value } });
      expect(wrapper.text()).toBe(label);
      expect(wrapper.props('value')).toBe(value);
      if (value === 'won') expect(wrapper.classes()).toContain('bg-n-teal-3');
      wrapper.unmount();
    }
  );

  it('preserves customer-defined labels and translates only known issue types', () => {
    const wrapper = mount({
      setup: useCommercialLabels,
      template:
        '<p>{{ statusLabel("Etapa do cliente") }} · {{ issueTypeLabel("technical") }}</p>',
    });
    expect(wrapper.text()).toBe('Etapa do cliente · Técnica');
    wrapper.unmount();
  });
});
