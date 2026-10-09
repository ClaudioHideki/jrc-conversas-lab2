import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import RenewalPipeline from './RenewalPipeline.vue';
import ConfigurationPanel from './ConfigurationPanel.vue';

const mocks = vi.hoisted(() => ({
  route: null,
  store: null,
  api: { configuration: vi.fn(), saveConfiguration: vi.fn() },
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', async original => ({
  ...(await original()),
  useStore: () => mocks.store,
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) => {
      if (key === 'RELATIONSHIP.RENEWAL_RANGE')
        return `${values.from}–${values.to} days`;
      if (key === 'RELATIONSHIP.RENEWAL_AFTER') return `${values.from}+ days`;
      return key;
    },
  }),
}));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: mocks.api }));

beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ params: { accountId: '12' } });
  mocks.store = { getters: reactive({ getCurrentUserID: 7 }) };
  mocks.api.configuration.mockResolvedValue({
    data: {
      scope_key: 'account',
      version: 3,
      weights: { adoption: 100 },
      rules: {
        renewal_window_days: [15, 30, 60, 90, 120],
        survey_automation_enabled: false,
      },
      history: [],
    },
  });
  mocks.api.saveConfiguration.mockResolvedValue({ data: {} });
});

describe('Native renewal configuration', () => {
  it('shows configured ranges and filters by stable keys while preserving the provided counters', async () => {
    const wrapper = mount(RenewalPipeline, {
      props: {
        windows: { 15: 2, 30: 3 },
        ranges: { 15: [0, 10], 30: [11, 25], later: [101, null] },
      },
    });
    const firstRange = wrapper
      .findAll('button')
      .find(button => button.text().includes('0–10 days'));
    expect(firstRange.text()).toContain('2');
    expect(wrapper.text()).toContain('11–25 days');
    expect(wrapper.text()).toContain('101+ days');
    await firstRange.trigger('click');
    expect(wrapper.emitted('filter')).toEqual([['15']]);
    wrapper.unmount();
  });

  it('submits integer window limits with the expected account and configuration version', async () => {
    const wrapper = mount(ConfigurationPanel, {
      props: { allowed: true },
      global: { stubs: { OperationsSettingsPanel: true } },
    });
    await flushPromises();
    const limits = wrapper
      .findAll('label')
      .find(label =>
        label.text().includes('RELATIONSHIP.RULE_LABELS.renewal_window_days')
      )
      .get('input');
    await limits.setValue('10, 25, 50, 75, 100');
    await limits.trigger('change');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(mocks.api.saveConfiguration).toHaveBeenCalledWith('12', {
      scope_key: 'account',
      version: 3,
      weights: { adoption: 100 },
      rules: {
        renewal_window_days: [10, 25, 50, 75, 100],
        survey_automation_enabled: false,
      },
    });
    wrapper.unmount();
  });
});
