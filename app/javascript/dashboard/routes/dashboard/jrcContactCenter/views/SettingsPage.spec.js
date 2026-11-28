import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import SettingsPage from './SettingsPage.vue';
import ContactCenterLayout from '../ContactCenterLayout.vue';

const mocks = vi.hoisted(() => ({ route: null, user: null }));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => mocks.user,
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    context: vi.fn(),
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
  mocks.user = ref({
    id: 7,
    accounts: [
      { id: 1, role: 'agent', permissions: ['jrc_contact_center_configure'] },
    ],
  });
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

  it('distinguishes an unobserved initial read from a real scoped zero count', async () => {
    let finish;
    API.administration.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = render();
    expect(
      wrapper
        .findAllComponents({ name: 'VisualMetricCard' })
        .map(card => card.props('value'))
    ).toEqual(['—', '—', '—', '—']);
    finish({
      data: { capabilities: { configure: true, configuration_global: true } },
    });
    await flushPromises();
    expect(
      wrapper
        .findAllComponents({ name: 'VisualMetricCard' })
        .map(card => card.props('value'))
    ).toEqual([0, 0, 0, 0]);
  });

  it('does not present a failed refresh as four observed zero metrics', async () => {
    const wrapper = render();
    await flushPromises();
    API.administration.mockRejectedValueOnce({ response: { status: 403 } });
    mocks.route.params.accountId = '2';
    await flushPromises();
    expect(
      wrapper
        .findAllComponents({ name: 'VisualMetricCard' })
        .map(card => card.props('value'))
    ).toEqual(['—', '—', '—', '—']);
    expect(wrapper.findComponent({ name: 'StructureEditor' }).exists()).toBe(
      false
    );
  });

  it('clears existing structural and global authority immediately when the same account profile changes', async () => {
    const wrapper = render();
    await flushPromises();
    let finish;
    API.administration.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    mocks.user.value.accounts[0].permissions = [];
    await flushPromises();
    expect(wrapper.findComponent({ name: 'AcwPolicyEditor' }).exists()).toBe(
      false
    );
    expect(wrapper.findComponent({ name: 'StructureEditor' }).exists()).toBe(
      false
    );
    expect(API.administration).toHaveBeenLastCalledWith('1');
    finish({
      data: { capabilities: { configure: false, configuration_global: false } },
    });
    await flushPromises();
    expect(wrapper.findComponent({ name: 'StructureEditor' }).exists()).toBe(
      false
    );
  });

  it('never restores a delayed old global grant after a same-account access change', async () => {
    let finish;
    API.administration.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = render();
    API.administration.mockResolvedValueOnce({
      data: { capabilities: { configure: false, configuration_global: false } },
    });
    mocks.user.value.accounts[0].custom_role_id = 91;
    await flushPromises();
    finish({
      data: { capabilities: { configure: true, configuration_global: true } },
    });
    await flushPromises();
    expect(wrapper.findComponent({ name: 'AcwPolicyEditor' }).exists()).toBe(
      false
    );
    expect(wrapper.findComponent({ name: 'StructureEditor' }).exists()).toBe(
      false
    );
  });

  it('retains the current editor for native presence-only updates without refetching authority', async () => {
    const wrapper = render();
    await flushPromises();
    const requests = API.administration.mock.calls.length;
    const editor = wrapper.getComponent({ name: 'StructureEditor' }).vm;
    mocks.user.value.accounts[0].availability_status = 'busy';
    mocks.user.value.accounts[0].active_at = 12345;
    await flushPromises();
    expect(API.administration).toHaveBeenCalledTimes(requests);
    expect(wrapper.getComponent({ name: 'StructureEditor' }).vm).toBe(editor);
  });

  it('loads current data when the authenticated actor changes within the same account', async () => {
    const wrapper = render();
    await flushPromises();
    API.administration.mockResolvedValueOnce({
      data: { capabilities: { configure: true, configuration_global: false } },
    });
    mocks.user.value.id = 8;
    await flushPromises();
    expect(API.administration).toHaveBeenCalledTimes(2);
    expect(wrapper.findComponent({ name: 'AcwPolicyEditor' }).exists()).toBe(
      false
    );
    expect(wrapper.get('[data-global-acw-denied]').exists()).toBe(true);
  });
});

describe('settings reads after native parent scope revocation', () => {
  it.each(['actor', 'membership'])(
    'does not start an obsolete six-endpoint batch on %s change',
    async change => {
      API.context
        .mockReset()
        .mockResolvedValue({ data: { capabilities: { configure: true } } });
      mocks.route.name = 'jrc_contact_center_settings';
      const wrapper = mount(ContactCenterLayout, {
        global: {
          mocks: { $t: key => key },
          stubs: {
            Icon: true,
            RouterLink: true,
            RouterView: {
              components: { SettingsPage },
              template: '<SettingsPage />',
            },
            VisualMetricCard: true,
            VisualStatusBadge: true,
            VisualSectionCard: { template: '<section><slot /></section>' },
            StructureEditor: true,
            AcwPolicyEditor: true,
          },
        },
      });
      await flushPromises();
      const endpoints = [
        API.units,
        API.queues,
        API.queueMemberships,
        API.routingRules,
        API.integrationCapabilities,
        API.administration,
      ];
      endpoints.forEach(endpoint => expect(endpoint).toHaveBeenCalledTimes(1));
      let release;
      API.context.mockImplementationOnce(
        () =>
          new Promise(resolve => {
            release = resolve;
          })
      );
      if (change === 'actor') mocks.user.value.id = 8;
      else mocks.user.value.accounts[0].permissions = [];
      await flushPromises();
      expect(wrapper.findComponent(SettingsPage).exists()).toBe(false);
      endpoints.forEach(endpoint => expect(endpoint).toHaveBeenCalledTimes(1));
      release({ data: { capabilities: { configure: true } } });
      await flushPromises();
      expect(wrapper.findComponent(SettingsPage).exists()).toBe(true);
      endpoints.forEach(endpoint => expect(endpoint).toHaveBeenCalledTimes(2));
      expect(API.context).toHaveBeenCalledTimes(2);
    }
  );
});
