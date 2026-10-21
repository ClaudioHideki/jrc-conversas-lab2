import { beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, nextTick, reactive } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import JrcContactCenterAPI from 'dashboard/api/jrcContactCenter';
import ContactCenterLayout from './ContactCenterLayout.vue';

const mocks = vi.hoisted(() => ({ route: null }));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { context: vi.fn() },
}));

const AccountView = defineComponent({
  setup: () => ({ initialAccount: mocks.route.params.accountId }),
  template: '<div data-testid="account-view">{{ initialAccount }}</div>',
});

describe('Contact Center account navigation', () => {
  beforeEach(() => {
    mocks.route = reactive({ params: { accountId: '1' } });
    JrcContactCenterAPI.context.mockResolvedValue({
      data: { capabilities: {} },
    });
  });

  it('discards the previous account view state when switching accounts', async () => {
    const wrapper = mount(ContactCenterLayout, {
      global: { stubs: { RouterLink: true, RouterView: AccountView } },
    });
    await flushPromises();
    expect(wrapper.get('[data-testid="account-view"]').text()).toBe('1');
    mocks.route.params.accountId = '2';
    await flushPromises();
    expect(wrapper.get('[data-testid="account-view"]').text()).toBe('2');
  });

  it('does not restore privileged navigation from an old account response', async () => {
    let resolveFirst;
    JrcContactCenterAPI.context.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveFirst = resolve;
        })
    );
    const wrapper = mount(ContactCenterLayout, {
      global: { stubs: { RouterLink: true, RouterView: true } },
    });
    mocks.route.params.accountId = '2';
    await flushPromises();
    resolveFirst({ data: { capabilities: { supervise: true } } });
    await flushPromises();
    expect(wrapper.text()).not.toContain('JRC_CONTACT_CENTER.NAV.SUPERVISOR');
  });

  it('does not mount the workspace when the account context rejects access', async () => {
    JrcContactCenterAPI.context.mockRejectedValueOnce(
      new Error('access denied')
    );
    const wrapper = mount(ContactCenterLayout, {
      global: { stubs: { RouterLink: true, RouterView: AccountView } },
    });
    await flushPromises();
    expect(wrapper.find('[data-testid="account-view"]').exists()).toBe(false);
    expect(wrapper.get('[role="alert"]').text()).toBe(
      'JRC_CONTACT_CENTER.COMMON.ERROR'
    );
  });

  it('discards the old workspace while the next account is still being authorized', async () => {
    let resolveNext;
    JrcContactCenterAPI.context
      .mockResolvedValueOnce({ data: { capabilities: {} } })
      .mockImplementationOnce(
        () =>
          new Promise(resolve => {
            resolveNext = resolve;
          })
      );
    const wrapper = mount(ContactCenterLayout, {
      global: { stubs: { RouterLink: true, RouterView: AccountView } },
    });
    await flushPromises();
    expect(wrapper.get('[data-testid="account-view"]').text()).toBe('1');
    mocks.route.params.accountId = '2';
    await nextTick();
    expect(wrapper.find('[data-testid="account-view"]').exists()).toBe(false);
    resolveNext({ data: { capabilities: {} } });
    await flushPromises();
    expect(wrapper.get('[data-testid="account-view"]').text()).toBe('2');
  });
  it('separates authorized navigation and keeps occurrences in CRM', async () => {
    JrcContactCenterAPI.context.mockResolvedValue({
      data: {
        capabilities: { supervise: true, configure: true, reports: true },
      },
    });
    const wrapper = mount(ContactCenterLayout, {
      global: { stubs: { RouterLink: true, RouterView: true } },
    });
    await flushPromises();
    ['AGENT', 'SUPERVISOR', 'CONTROL_DESK', 'MONITORING', 'SETTINGS'].forEach(
      group => {
        expect(wrapper.text()).toContain(
          `JRC_CONTACT_CENTER.NAV_GROUPS.${group}`
        );
      }
    );
    expect(wrapper.text()).not.toContain('JRC_CONTACT_CENTER.NAV.OCCURRENCES');
  });

  it('keeps ordinary agent navigation limited to the four attendance pages', async () => {
    const wrapper = mount(ContactCenterLayout, {
      global: { stubs: { RouterLink: true, RouterView: true } },
    });
    await flushPromises();
    const links = wrapper.findAllComponents({ name: 'RouterLink' });
    expect(links.map(link => link.attributes('to'))).toHaveLength(4);
    expect(wrapper.text()).toContain('JRC_CONTACT_CENTER.NAV_GROUPS.AGENT');
    expect(wrapper.text()).not.toContain(
      'JRC_CONTACT_CENTER.NAV_GROUPS.SUPERVISOR'
    );
  });
});
