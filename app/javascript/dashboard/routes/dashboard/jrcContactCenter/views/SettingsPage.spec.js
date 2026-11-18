import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import SettingsPage from './SettingsPage.vue';

const mocks = vi.hoisted(() => ({ route: null }));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    units: vi.fn(),
    queues: vi.fn(),
    queueMemberships: vi.fn(),
    routingRules: vi.fn(),
    integrationCapabilities: vi.fn(),
    administration: vi.fn(),
  },
}));
const render = () =>
  mount(SettingsPage, {
    global: {
      mocks: { $t: key => key },
      stubs: {
        Icon: true,
        VisualMetricCard: true,
        VisualStatusBadge: true,
        VisualSectionCard: { template: '<section><slot /></section>' },
        StructureEditor: true,
        AcwPolicyEditor: true,
      },
    },
  });
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ params: { accountId: '1' } });
  [API.units, API.queues, API.queueMemberships, API.routingRules].forEach(
    method => method.mockResolvedValue({ data: { items: [] } })
  );
  API.integrationCapabilities.mockResolvedValue({
    data: { provider: 'synthetic-local' },
  });
  API.administration.mockResolvedValue({
    data: { capabilities: { configure: true, configuration_global: true } },
  });
});

describe('native legacy settings global ACW authority', () => {
  it('uses the existing administrative metadata and preserves the global and structural editors', async () => {
    const wrapper = render();
    await flushPromises();
    expect(API.administration).toHaveBeenCalledWith('1');
    expect(
      wrapper.getComponent({ name: 'AcwPolicyEditor' }).props('accountId')
    ).toBe('1');
    expect(wrapper.findComponent({ name: 'StructureEditor' }).exists()).toBe(
      true
    );
    expect(wrapper.find('[data-global-acw-denied]').exists()).toBe(false);
  });
  it('preserves scoped structure editing without offering the global policy editor', async () => {
    API.administration.mockResolvedValueOnce({
      data: { capabilities: { configure: true, configuration_global: false } },
    });
    const wrapper = render();
    await flushPromises();
    expect(wrapper.findComponent({ name: 'AcwPolicyEditor' }).exists()).toBe(
      false
    );
    expect(wrapper.findComponent({ name: 'StructureEditor' }).exists()).toBe(
      true
    );
    expect(wrapper.get('[data-global-acw-denied]').text()).toBe(
      'JRC_CONTACT_CENTER.ADMIN.ACW_GLOBAL_DENIED'
    );
  });
  it('does not substitute a global indicator for the actual configure permission', async () => {
    API.administration.mockResolvedValueOnce({
      data: { capabilities: { configure: false, configuration_global: true } },
    });
    const wrapper = render();
    await flushPromises();
    expect(wrapper.findComponent({ name: 'AcwPolicyEditor' }).exists()).toBe(
      false
    );
    expect(wrapper.findComponent({ name: 'StructureEditor' }).exists()).toBe(
      false
    );
  });
  it('clears old global authority while the new account is loaded and ignores its delayed response', async () => {
    let finish;
    API.administration.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = render();
    await flushPromises();
    API.administration.mockResolvedValue({
      data: { capabilities: { configure: true, configuration_global: false } },
    });
    mocks.route.params.accountId = '2';
    await flushPromises();
    finish({
      data: { capabilities: { configure: true, configuration_global: true } },
    });
    await flushPromises();
    expect(API.administration).toHaveBeenLastCalledWith('2');
    expect(wrapper.findComponent({ name: 'AcwPolicyEditor' }).exists()).toBe(
      false
    );
    expect(wrapper.find('[data-global-acw-denied]').exists()).toBe(true);
  });
  it('does not retain authority after an administrative metadata read fails', async () => {
    const wrapper = render();
    await flushPromises();
    API.administration.mockRejectedValueOnce({ response: { status: 401 } });
    mocks.route.params.accountId = '2';
    await flushPromises();
    expect(wrapper.findComponent({ name: 'AcwPolicyEditor' }).exists()).toBe(
      false
    );
    expect(wrapper.text()).toContain('JRC_CONTACT_CENTER.COMMON.ERROR');
  });
});
