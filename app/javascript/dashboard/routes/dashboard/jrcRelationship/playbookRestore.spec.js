import { mount, shallowMount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import messages from 'dashboard/i18n/locale/en/relationship.json';
import Restore from './PlaybookRestoreDialog.vue';
import Summary from './PlaybookDefinitionSummary.vue';
import Preview from './PlaybookDesignPreview.vue';
import Panel from './ConfigurationPanel.vue';
const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  api: {
    playbooks: vi.fn(),
    restorePlaybook: vi.fn(),
    playbookOptions: vi.fn(),
    previewPlaybook: vi.fn(),
    portfolioBatch: vi.fn(),
  },
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', async original => ({
  ...(await original()),
  useStore: () => mocks.store,
}));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: mocks.api }));
const Dialog = {
  setup(_, { expose }) {
    expose({ open: vi.fn() });
  },
  template: '<section><slot /></section>',
};
const definition = {
  name: 'Saved historical definition',
  active: false,
  trigger_kind: 'health',
  steps: [
    {
      kind: 'activity',
      step_key: 'one',
      title: 'Historical native activity',
      after_days: 2,
    },
  ],
  conditions: [{ field: 'health_score', operator: 'lt', value: 60 }],
};
const historical = { version: 1, payload: definition };
const current = {
  ...definition,
  id: 18,
  version: 3,
  name: 'Current saved definition',
  history: [historical],
  conditions: [{ field: 'health_score', operator: 'lt', value: 50 }],
};
const wrappers = [];
const render = (
  component = Restore,
  props = { current, historical, allowed: true },
  shallow = false
) => {
  const wrapper = (shallow ? shallowMount : mount)(component, {
    props,
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: messages } }),
      ],
      stubs: { Dialog },
    },
  });
  wrappers.push(wrapper);
  return wrapper;
};
const button = (wrapper, text) =>
  wrapper.findAll('button').find(row => row.text() === text);
const review = async wrapper => {
  await button(wrapper, 'Reason and confirmation').trigger('click');
  await wrapper.get('textarea').setValue('Reviewed historical definition');
};
beforeEach(() => {
  vi.resetAllMocks();
  mocks.route = reactive({ params: { accountId: '1400' } });
  mocks.store = reactive({
    getters: {
      getCurrentUserID: 7,
      getCurrentRole: 'administrator',
      getCurrentUser: { accounts: [] },
    },
  });
  mocks.api.playbooks.mockImplementation(async () => ({
    data: { payload: [structuredClone(current)] },
  }));
  mocks.api.restorePlaybook.mockResolvedValue({
    data: { id: 18, version: 4, restored_from_version: 1 },
  });
  mocks.api.playbookOptions.mockResolvedValue({
    data: {
      assignments: [[19, 'Authorized customer']],
      flows: [{ id: 61, name: 'Published native flow' }],
      contacts: [],
      conversations: [],
    },
  });
  mocks.api.previewPlaybook.mockResolvedValue({
    data: {
      state: 'preview',
      matched: true,
      version: 3,
      steps: [
        {
          kind: 'flow',
          step_key: 'approved',
          approval_token: 'synthetic-only',
          approval_expires_at: new Date(Date.now() + 120000).toISOString(),
        },
      ],
    },
  });
});
afterEach(() => wrappers.splice(0).forEach(wrapper => wrapper.unmount()));

it('compares native conditions, steps and enabled state without writing or executing anything', async () => {
  const wrapper = render();
  expect(wrapper.findAllComponents(Summary)).toHaveLength(2);
  expect(wrapper.text()).toContain('Historical native activity');
  expect(wrapper.text()).toContain('Health score less than 60');
  expect(wrapper.text()).toContain('Health score less than 50');
  expect(mocks.api.restorePlaybook).not.toHaveBeenCalled();
  expect(mocks.api.portfolioBatch).not.toHaveBeenCalled();
});

it('reuses the native preview with fixed historical references and execution explicitly unavailable', async () => {
  const wrapper = render();
  await button(wrapper, 'Simulate definition').trigger('click');
  await flushPromises();
  const preview = wrapper.findComponent(Preview);
  expect(preview.props()).toMatchObject({
    simulationOnly: true,
    readOnlyDefinition: true,
    book: { ...definition, id: 18, version: 3 },
  });
  expect(mocks.api.restorePlaybook).not.toHaveBeenCalled();
  expect(mocks.api.portfolioBatch).not.toHaveBeenCalled();
});

it('requires an explicit reason and confirms the exact native playbook/new-version/source receipt', async () => {
  const wrapper = render();
  await review(wrapper);
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(mocks.api.restorePlaybook).toHaveBeenCalledWith('1400', 18, {
    version: 3,
    source_version: 1,
    reason: 'Reviewed historical definition',
  });
  expect(wrapper.emitted('saved')).toEqual([
    [{ id: 18, version: 4, restored_from_version: 1 }],
  ]);
});

it('retains the reason and prevents automatic retry after a wrong receipt or native conflict', async () => {
  mocks.api.restorePlaybook.mockResolvedValueOnce({
    data: { id: 99, version: 4, restored_from_version: 1 },
  });
  const wrapper = render();
  await review(wrapper);
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(wrapper.emitted('saved')).toBeUndefined();
  expect(wrapper.get('textarea').element.value).toBe(
    'Reviewed historical definition'
  );
  await wrapper.get('form').trigger('submit');
  expect(mocks.api.restorePlaybook).toHaveBeenCalledOnce();
});

it('keeps incomplete legacy snapshots read-only and does not substitute current fields for missing history', async () => {
  const wrapper = render(Restore, {
    current,
    historical: {
      version: 1,
      payload: { name: 'Incomplete legacy definition' },
    },
    allowed: true,
  });
  expect(wrapper.get('[role="alert"]').text()).toContain('incomplete');
  expect(button(wrapper, 'Simulate definition')).toBeUndefined();
  await review(wrapper);
  await wrapper.get('form').trigger('submit');
  expect(mocks.api.restorePlaybook).not.toHaveBeenCalled();
});

it('drops a late saved response after role changes and prevents further writes from that dialog', async () => {
  let resolve;
  mocks.api.restorePlaybook.mockReturnValueOnce(
    new Promise(done => {
      resolve = done;
    })
  );
  const wrapper = render();
  await review(wrapper);
  await wrapper.get('form').trigger('submit');
  mocks.store.getters.getCurrentRole = 'agent';
  await flushPromises();
  resolve({ data: { id: 18, version: 4, restored_from_version: 1 } });
  await flushPromises();
  expect(wrapper.emitted('saved')).toBeUndefined();
  expect(wrapper.emitted('close')).toHaveLength(1);
  await wrapper.get('form').trigger('submit');
  expect(mocks.api.restorePlaybook).toHaveBeenCalledOnce();
});

it('freshly reads the native book/history before review and confirms saved state only after native readback', async () => {
  const wrapper = render(
    Panel,
    { screen: 'playbooks', allowed: true, metadata: {} },
    true
  );
  await flushPromises();
  await button(wrapper, 'Review playbook restoration').trigger('click');
  await flushPromises();
  expect(mocks.api.playbooks).toHaveBeenCalledTimes(2);
  expect(wrapper.findComponent(Restore).props('current')).toEqual(current);
  mocks.api.playbooks.mockResolvedValue({
    data: { payload: [{ ...current, version: 4, name: definition.name }] },
  });
  wrapper
    .findComponent(Restore)
    .vm.$emit('saved', { id: 18, version: 4, restored_from_version: 1 });
  await flushPromises();
  expect(wrapper.findComponent(Restore).exists()).toBe(false);
  expect(wrapper.text()).toContain('Playbook version 4 saved from version 1');
});

it('does not reopen an old native history read after current account membership changes', async () => {
  const wrapper = render(
    Panel,
    { screen: 'playbooks', allowed: true, metadata: {} },
    true
  );
  await flushPromises();
  let resolve;
  mocks.api.playbooks.mockReturnValueOnce(
    new Promise(done => {
      resolve = done;
    })
  );
  await button(wrapper, 'Review playbook restoration').trigger('click');
  mocks.api.playbooks.mockRejectedValue({ response: { status: 403 } });
  mocks.store.getters.getCurrentRole = 'agent';
  await flushPromises();
  resolve({ data: { payload: [current] } });
  await flushPromises();
  expect(wrapper.findComponent(Restore).exists()).toBe(false);
  expect(wrapper.text()).not.toContain('Current saved definition');
});

it('never enables native Flow execution in simulation-only mode, even when a simulated approval token is returned', async () => {
  const book = {
    id: 18,
    version: 3,
    active: true,
    name: 'Synthetic enabled preview',
    steps: [
      {
        kind: 'flow',
        title: 'Historical flow',
        step_key: 'flow',
        flow_id: 61,
        message_id: 5,
      },
    ],
  };
  const wrapper = render(Preview, {
    book,
    simulationOnly: true,
    readOnlyDefinition: true,
  });
  await flushPromises();
  expect(wrapper.get('fieldset').attributes('disabled')).toBeDefined();
  await wrapper.get('select').setValue('19');
  await flushPromises();
  await button(
    wrapper,
    messages.RELATIONSHIP.PLAYBOOK_PREVIEW.SIMULATE
  ).trigger('click');
  await flushPromises();
  expect(mocks.api.previewPlaybook).toHaveBeenCalledOnce();
  expect(wrapper.find('[data-testid="run-approved-playbook"]').exists()).toBe(
    false
  );
  expect(mocks.api.portfolioBatch).not.toHaveBeenCalled();
  expect(wrapper.emitted('updateStep')).toBeUndefined();
});
