import { mount, shallowMount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import messages from 'dashboard/i18n/locale/en/relationship.json';
import Restore from './ConfigurationRestoreDialog.vue';
import Preview from './HealthConfigurationPreview.vue';
import Panel from './ConfigurationPanel.vue';
const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  api: { configuration: vi.fn(), restoreConfiguration: vi.fn() },
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
const historical = {
  version: 1,
  weights: { relationship: 100 },
  rules: {
    healthy_threshold: 70,
    required_documents: [],
    portfolio_capacity_limits: [],
  },
};
const current = {
  scope_key: 'account',
  version: 3,
  weights: { relationship: 100 },
  rules: { ...historical.rules, healthy_threshold: 80 },
  history: [historical],
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
      stubs: { Dialog, HealthConfigurationPreview: true },
    },
  });
  wrappers.push(wrapper);
  return wrapper;
};
const button = (wrapper, text) =>
  wrapper.findAll('button').find(row => row.text() === text);
const review = async wrapper => {
  await button(wrapper, 'Reason and confirmation').trigger('click');
  await wrapper.get('textarea').setValue('Explicit scoped restoration reason');
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
  mocks.api.configuration.mockImplementation(async () => ({
    data: structuredClone(current),
  }));
  mocks.api.restoreConfiguration.mockResolvedValue({
    data: { scope_key: 'account', version: 4, restored_from_version: 1 },
  });
});
afterEach(() => wrappers.splice(0).forEach(wrapper => wrapper.unmount()));

it('compares saved values and reuses native health simulation with the current revision and historical draft', async () => {
  const wrapper = render();
  expect(wrapper.text()).toContain('80');
  expect(wrapper.text()).toContain('70');
  expect(wrapper.find('form').exists()).toBe(false);
  await button(wrapper, 'Simulate health impact').trigger('click');
  expect(wrapper.findComponent(Preview).props('configuration')).toEqual({
    ...historical,
    scope_key: 'account',
    version: 3,
  });
  expect(mocks.api.restoreConfiguration).not.toHaveBeenCalled();
});

it('posts only a pinned scope and versions with explicit reason and confirms the actual returned receipt', async () => {
  const wrapper = render();
  await review(wrapper);
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(mocks.api.restoreConfiguration).toHaveBeenCalledWith('1400', {
    scope_key: 'account',
    version: 3,
    source_version: 1,
    reason: 'Explicit scoped restoration reason',
  });
  expect(wrapper.emitted('saved')).toEqual([
    [{ scope_key: 'account', version: 4, restored_from_version: 1 }],
  ]);
});

it('does not confirm bare or wrong-scope HTTP200 receipts and retains the bounded review reason', async () => {
  mocks.api.restoreConfiguration.mockResolvedValue({
    data: { scope_key: 'unit:99', version: 4, restored_from_version: 1 },
  });
  const wrapper = render();
  await review(wrapper);
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(wrapper.emitted('saved')).toBeUndefined();
  expect(wrapper.get('textarea').element.value).toBe(
    'Explicit scoped restoration reason'
  );
  expect(wrapper.get('button[type="submit"]').element.disabled).toBe(true);
});

it('requires explicit reopen after a native conflict or unknown commit result without automatically retrying', async () => {
  mocks.api.restoreConfiguration.mockRejectedValueOnce({
    response: { status: 409, data: { errors: ['Configuration changed'] } },
  });
  const wrapper = render();
  await review(wrapper);
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(wrapper.get('[role="alert"]').text()).toContain(
    'Configuration changed'
  );
  await wrapper.get('form').trigger('submit');
  expect(mocks.api.restoreConfiguration).toHaveBeenCalledOnce();
  expect(wrapper.emitted('saved')).toBeUndefined();
});

it('keeps validation errors editable while preventing writes without permission or a reason', async () => {
  mocks.api.restoreConfiguration.mockRejectedValueOnce({
    response: { status: 422, data: { errors: ['Native rule validation'] } },
  });
  const wrapper = render();
  await button(wrapper, 'Reason and confirmation').trigger('click');
  await wrapper.get('form').trigger('submit');
  expect(mocks.api.restoreConfiguration).not.toHaveBeenCalled();
  await wrapper.get('textarea').setValue('Reviewed validation reason');
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(wrapper.get('button[type="submit"]').element.disabled).toBe(false);
  await wrapper.setProps({ allowed: false });
  await wrapper.get('form').trigger('submit');
  expect(mocks.api.restoreConfiguration).toHaveBeenCalledOnce();
});

it('drops a late restoration response after current identity changes', async () => {
  let resolve;
  mocks.api.restoreConfiguration.mockReturnValue(
    new Promise(done => {
      resolve = done;
    })
  );
  const wrapper = render();
  await review(wrapper);
  await wrapper.get('form').trigger('submit');
  mocks.store.getters.getCurrentRole = 'agent';
  await flushPromises();
  resolve({
    data: { scope_key: 'account', version: 4, restored_from_version: 1 },
  });
  await flushPromises();
  expect(wrapper.emitted('close')).toHaveLength(1);
  expect(wrapper.emitted('saved')).toBeUndefined();
});

it('pins a group revision and does not offer a health simulation for distribution-only group rules', async () => {
  const wrapper = render(Restore, {
    current: { ...current, scope_key: 'portfolio:18', portfolio_revision: 5 },
    historical,
    allowed: true,
  });
  expect(button(wrapper, 'Simulate health impact')).toBeUndefined();
  await review(wrapper);
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(mocks.api.restoreConfiguration.mock.calls[0][1]).toMatchObject({
    scope_key: 'portfolio:18',
    portfolio_revision: 5,
  });
  expect(wrapper.emitted('saved')).toBeUndefined();
});

it('freshly reads the saved configuration before opening a restore review and preserves unsaved edits on cancel', async () => {
  const wrapper = render(Panel, { allowed: true, metadata: {} }, true);
  await flushPromises();
  await wrapper
    .get('[data-testid="relationship-rule-healthy_threshold"]')
    .setValue('85');
  await button(wrapper, 'Review restoration').trigger('click');
  await flushPromises();
  expect(mocks.api.configuration).toHaveBeenCalledTimes(2);
  expect(
    wrapper.findComponent(Restore).props('current').rules.healthy_threshold
  ).toBe(80);
  wrapper.findComponent(Restore).vm.$emit('close');
  await flushPromises();
  expect(
    wrapper.get('[data-testid="relationship-rule-healthy_threshold"]').element
      .value
  ).toBe('85');
  expect(mocks.api.restoreConfiguration).not.toHaveBeenCalled();
});

it('does not open a late historical read after the current role changes', async () => {
  const wrapper = render(Panel, { allowed: true, metadata: {} }, true);
  await flushPromises();
  let resolve;
  mocks.api.configuration.mockReturnValueOnce(
    new Promise(done => {
      resolve = done;
    })
  );
  await button(wrapper, 'Review restoration').trigger('click');
  mocks.api.configuration.mockRejectedValue({ response: { status: 403 } });
  mocks.store.getters.getCurrentRole = 'agent';
  await flushPromises();
  resolve({ data: structuredClone(current) });
  await flushPromises();
  expect(wrapper.findComponent(Restore).exists()).toBe(false);
  expect(
    wrapper.find('[data-testid="relationship-rule-healthy_threshold"]').exists()
  ).toBe(false);
});

it('reloads native persistence before displaying the confirmed restored version', async () => {
  const wrapper = render(Panel, { allowed: true, metadata: {} }, true);
  await flushPromises();
  await button(wrapper, 'Review restoration').trigger('click');
  await flushPromises();
  mocks.api.configuration.mockResolvedValue({
    data: { ...current, version: 4, rules: historical.rules },
  });
  wrapper.findComponent(Restore).vm.$emit('saved', {
    scope_key: 'account',
    version: 4,
    restored_from_version: 1,
  });
  await flushPromises();
  expect(wrapper.findComponent(Restore).exists()).toBe(false);
  expect(wrapper.text()).toContain('Version 4 saved from version 1');
  expect(
    wrapper.get('[data-testid="relationship-rule-healthy_threshold"]').element
      .value
  ).toBe('70');
});

it('shows native structured capacity history without missing labels or object-placeholder text', async () => {
  mocks.api.configuration.mockResolvedValue({
    data: {
      ...current,
      history: [
        {
          ...historical,
          rules: {
            required_documents: [],
            portfolio_capacity_limits: [
              {
                user_id: 7,
                unit: 'hours',
                maximum: 12,
                availability: 1,
                dedication: 1,
              },
            ],
          },
        },
      ],
    },
  });
  const wrapper = render(Panel, { allowed: true, metadata: {} }, true);
  await flushPromises();
  expect(wrapper.text()).toContain('Analyst capacity limits');
  expect(wrapper.text()).toContain('Required customer documents');
  expect(wrapper.text()).toContain('"maximum":12');
  expect(wrapper.text()).not.toContain('[object Object]');
  expect(wrapper.text()).not.toContain('RELATIONSHIP.RULE_LABELS.');
});

it('looks up an older stored configuration directly and preserves the current unsaved draft when review is cancelled', async () => {
  const saved = { ...current, version: 76 };
  mocks.api.configuration
    .mockResolvedValueOnce({ data: { ...structuredClone(saved), history: [] } })
    .mockResolvedValue({ data: structuredClone(saved) });
  const wrapper = render(Panel, { allowed: true, metadata: {} }, true);
  await flushPromises();
  await wrapper
    .get('[data-testid="relationship-rule-healthy_threshold"]')
    .setValue('85');
  const selector = wrapper.get('[data-testid="configuration-stored-version"]');
  expect(selector.get('input').attributes('max')).toBe('75');
  await selector.get('input').setValue('1');
  await selector.trigger('submit');
  await flushPromises();
  expect(mocks.api.configuration).toHaveBeenLastCalledWith('1400', {
    params: { scope_key: 'account', source_version: 1 },
  });
  expect(wrapper.findComponent(Restore).props('historical')).toEqual(
    historical
  );
  expect(
    wrapper.findComponent(Restore).props('current').rules.healthy_threshold
  ).toBe(80);
  wrapper.findComponent(Restore).vm.$emit('close');
  await flushPromises();
  expect(
    wrapper.get('[data-testid="relationship-rule-healthy_threshold"]').element
      .value
  ).toBe('85');
  expect(mocks.api.restoreConfiguration).not.toHaveBeenCalled();
});

it('does not invent a missing stored source or open its confirmation dialog', async () => {
  mocks.api.configuration.mockResolvedValue({
    data: { ...structuredClone(current), history: [] },
  });
  const wrapper = render(Panel, { allowed: true, metadata: {} }, true);
  await flushPromises();
  const selector = wrapper.get('[data-testid="configuration-stored-version"]');
  await selector.get('input').setValue('1');
  await selector.trigger('submit');
  await flushPromises();
  expect(wrapper.findComponent(Restore).exists()).toBe(false);
  expect(wrapper.get('[role="alert"]').text()).toBe(
    messages.RELATIONSHIP.CONFIG_RESTORE.UNCONFIRMED
  );
  expect(mocks.api.restoreConfiguration).not.toHaveBeenCalled();
});

it.each(['0', '-1', '3', '1.5'])(
  'does not fetch invalid stored source %s even on a programmatic form submit',
  async value => {
    const wrapper = render(Panel, { allowed: true, metadata: {} }, true);
    await flushPromises();
    const selector = wrapper.get(
      '[data-testid="configuration-stored-version"]'
    );
    await selector.get('input').setValue(value);
    await selector.trigger('submit');
    await flushPromises();
    expect(mocks.api.configuration).toHaveBeenCalledOnce();
    expect(wrapper.findComponent(Restore).exists()).toBe(false);
  }
);

it('pages immutable history while preserving unsaved rules and reuses a fresh native restore review', async () => {
  const saved = {
    ...structuredClone(current),
    version: 76,
    history: [{ ...historical, version: 76 }],
    history_meta: { page: 1, per_page: 25, total: 76 },
  };
  mocks.api.configuration.mockResolvedValueOnce({
    data: structuredClone(saved),
  });
  const wrapper = render(Panel, { allowed: true, metadata: {} }, true);
  await flushPromises();
  expect(mocks.api.configuration.mock.calls[0][1].params).toEqual({
    scope_key: 'account',
    history_page: 1,
    history_per_page: 25,
  });
  await wrapper
    .get('[data-testid="relationship-rule-healthy_threshold"]')
    .setValue('85');
  mocks.api.configuration.mockResolvedValueOnce({
    data: {
      ...saved,
      rules: { healthy_threshold: 10 },
      history: [{ ...historical, version: 51 }],
      history_meta: { page: 2, per_page: 25, total: 76 },
    },
  });
  await wrapper
    .get('[data-test="configuration-history-next"]')
    .trigger('click');
  await flushPromises();
  expect(mocks.api.configuration.mock.lastCall[1].params).toEqual({
    scope_key: 'account',
    history_page: 2,
    history_per_page: 25,
  });
  expect(
    wrapper.get('[data-testid="relationship-rule-healthy_threshold"]').element
      .value
  ).toBe('85');
  mocks.api.configuration.mockResolvedValueOnce({
    data: { ...saved, history: [{ ...historical, version: 51 }] },
  });
  await button(wrapper, messages.RELATIONSHIP.CONFIG_RESTORE.OPEN).trigger(
    'click'
  );
  await flushPromises();
  expect(mocks.api.configuration.mock.lastCall[1].params).toEqual({
    scope_key: 'account',
    source_version: 51,
  });
  expect(wrapper.findComponent(Restore).props('historical').version).toBe(51);
  expect(
    wrapper.findComponent(Restore).props('current').rules.healthy_threshold
  ).toBe(80);
  wrapper.findComponent(Restore).vm.$emit('close');
  await flushPromises();
  expect(
    wrapper.get('[data-testid="relationship-rule-healthy_threshold"]').element
      .value
  ).toBe('85');
  expect(mocks.api.restoreConfiguration).not.toHaveBeenCalled();
});

it('retains the old page and current draft after malformed history metadata instead of accepting another scope', async () => {
  const saved = {
    ...structuredClone(current),
    version: 76,
    history_meta: { page: 1, per_page: 25, total: 76 },
  };
  mocks.api.configuration.mockResolvedValueOnce({
    data: structuredClone(saved),
  });
  const wrapper = render(Panel, { allowed: true, metadata: {} }, true);
  await flushPromises();
  await wrapper
    .get('[data-testid="relationship-rule-healthy_threshold"]')
    .setValue('85');
  mocks.api.configuration.mockResolvedValueOnce({
    data: {
      ...saved,
      scope_key: 'company:999',
      history: [{ ...historical, version: 2 }],
      history_meta: { page: 2, per_page: 25, total: 76 },
    },
  });
  await wrapper
    .get('[data-test="configuration-history-next"]')
    .trigger('click');
  await flushPromises();
  expect(wrapper.get('[role="alert"]').text()).toBe(
    messages.RELATIONSHIP.CONFIG_HISTORY_PAGE.UNCONFIRMED
  );
  expect(
    wrapper.get('[data-testid="relationship-rule-healthy_threshold"]').element
      .value
  ).toBe('85');
  expect(
    wrapper.get('[data-test="configuration-history-previous"]').element.disabled
  ).toBe(true);
});

it('aborts a pending history page and ignores its old payload after a native role change', async () => {
  const saved = {
    ...structuredClone(current),
    version: 76,
    history_meta: { page: 1, per_page: 25, total: 76 },
  };
  mocks.api.configuration.mockResolvedValueOnce({
    data: structuredClone(saved),
  });
  const wrapper = render(Panel, { allowed: true, metadata: {} }, true);
  await flushPromises();
  let finish;
  mocks.api.configuration.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await wrapper
    .get('[data-test="configuration-history-next"]')
    .trigger('click');
  await flushPromises();
  const options = mocks.api.configuration.mock.lastCall[1];
  mocks.api.configuration.mockRejectedValueOnce({
    response: { status: 403, data: { error: 'Native configure denied' } },
  });
  mocks.store.getters.getCurrentRole = 'agent';
  await flushPromises();
  finish({
    data: { ...saved, history_meta: { page: 2, per_page: 25, total: 76 } },
  });
  await flushPromises();
  expect(options.signal.aborted).toBe(true);
  expect(
    wrapper.find('[data-testid="relationship-rule-healthy_threshold"]').exists()
  ).toBe(false);
  expect(wrapper.get('[role="alert"]').text()).toContain(
    'Native configure denied'
  );
});

it('uses read-only reload for the current history page without persisting the draft', async () => {
  const saved = {
    ...structuredClone(current),
    history_meta: { page: 1, per_page: 25, total: 1 },
  };
  mocks.api.configuration.mockResolvedValue({ data: saved });
  const wrapper = render(Panel, { allowed: true, metadata: {} }, true);
  await flushPromises();
  await wrapper
    .get('[data-test="configuration-history-reload"]')
    .trigger('click');
  await flushPromises();
  expect(mocks.api.configuration).toHaveBeenCalledTimes(2);
  expect(mocks.api.configuration.mock.lastCall[1].params).toEqual({
    scope_key: 'account',
    history_page: 1,
    history_per_page: 25,
  });
  expect(
    wrapper.get('[data-test="configuration-history-next"]').element.disabled
  ).toBe(true);
  expect(mocks.api.restoreConfiguration).not.toHaveBeenCalled();
});
