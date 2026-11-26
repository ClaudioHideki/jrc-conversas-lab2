import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import LiveReports from '../LiveReports.vue';

const state = vi.hoisted(() => ({ operations: null, store: null }));
vi.mock('vuex', () => ({ useStore: () => state.store }));
vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({ isFeatureFlagEnabled: () => true }),
}));
vi.mock('../../../jrcOperations/useOperations', () => ({
  useOperations: () => state.operations,
}));
vi.mock('../Index.vue', () => ({
  __esModule: true,
  default: { template: '<div data-report="conversations" />' },
}));
vi.mock('../../../crm/views/reports/ReportsView.vue', () => ({
  __esModule: true,
  default: { template: '<div data-report="crm" />' },
}));
vi.mock('../components/ServiceDeskReportsTab.vue', () => ({
  __esModule: true,
  default: { template: '<div data-report="desk" />' },
}));
vi.mock('../../../jrcOperations/views/ProjectList.vue', () => ({
  __esModule: true,
  default: {
    props: { reportOnly: Boolean },
    template: '<div data-report="projects" :data-readonly="reportOnly" />',
  },
}));

enableAutoUnmount(afterEach);

const render = () =>
  mount(LiveReports, {
    global: { plugins: [createI18n({ legacy: false, locale: 'pt_BR' })] },
  });
const click = async (wrapper, label) => {
  await wrapper
    .findAll('button')
    .find(button => button.text() === label)
    .trigger('click');
  await flushPromises();
};

beforeEach(() => {
  state.operations = {
    accountId: ref('1'),
    userId: ref(1),
    status: ref({ projects_enabled: true, can_view_project_reports: true }),
  };
  state.store = {
    getters: {
      getCurrentUser: { accounts: [{ id: 1, permissions: ['jrc_crm'] }] },
    },
  };
  HTMLDialogElement.prototype.showModal = function showModal() {
    this.setAttribute('open', '');
  };
  HTMLDialogElement.prototype.close = function close() {
    this.removeAttribute('open');
  };
});

describe('central report catalog', () => {
  it('opens reports in a closable dialog and preserves the selected tab', async () => {
    const wrapper = render();
    await click(wrapper, 'Relatório de conversas');
    await vi.waitFor(() =>
      expect(
        wrapper
          .get('dialog[open]')
          .find('[data-report="conversations"]')
          .exists()
      ).toBe(true)
    );
    await wrapper.get('dialog').trigger('cancel');
    expect(wrapper.find('dialog').exists()).toBe(false);
    expect(wrapper.text()).toContain('Relatório de conversas');

    await click(wrapper, 'CRM');
    await click(wrapper, 'Indicadores do CRM');
    await vi.waitFor(() =>
      expect(wrapper.find('[data-report="crm"]').exists()).toBe(true)
    );
    await wrapper.get('dialog button').trigger('click');
    expect(wrapper.find('dialog').exists()).toBe(false);
    expect(wrapper.text()).toContain('Indicadores do CRM');

    await click(wrapper, 'Service Desk');
    await vi.waitFor(() =>
      expect(wrapper.find('[data-report="desk"]').exists()).toBe(true)
    );
    await click(wrapper, 'Projetos');
    await click(wrapper, 'Indicadores e exportação de projetos');
    await vi.waitFor(() =>
      expect(
        wrapper.get('[data-report="projects"]').attributes('data-readonly')
      ).toBe('true')
    );
  });

  it('closes the report when its scope changes and hides tabs without access', async () => {
    const wrapper = render();
    await click(wrapper, 'Projetos');
    await click(wrapper, 'Indicadores e exportação de projetos');
    expect(wrapper.find('dialog[open]').exists()).toBe(true);

    state.operations.status.value.can_view_project_reports = false;
    await flushPromises();
    expect(wrapper.find('dialog').exists()).toBe(false);
    expect(
      wrapper.findAll('nav button').map(button => button.text())
    ).not.toContain('Projetos');

    state.operations.accountId.value = '2';
    await flushPromises();
    expect(
      wrapper.findAll('nav button').map(button => button.text())
    ).not.toContain('CRM');
  });
});
