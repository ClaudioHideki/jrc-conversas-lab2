import { afterEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, mount, RouterLinkStub } from '@vue/test-utils';
import AdministrationPendingAlerts from './AdministrationPendingAlerts.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params = {}) => [key, ...Object.values(params)].join(' '),
  }),
}));
const render = context =>
  mount(AdministrationPendingAlerts, {
    props: { accountId: '7', context, query: { native_navigation: '1' } },
    global: { stubs: { RouterLink: RouterLinkStub, Icon: true } },
  });
enableAutoUnmount(afterEach);

describe('native administrative pending sources', () => {
  it('shows the actual missing configuration without an online or synchronized claim', () => {
    const wrapper = render({
      cards: [{ key: 'pabx' }],
      provider: { configured: false },
    });
    expect(wrapper.get('[data-native-provider-alert]').text()).toContain(
      'PENDING_ALERTS.NOT_CONFIGURED'
    );
    expect(wrapper.getComponent(RouterLinkStub).props('to')).toEqual({
      name: 'jrc_contact_center_admin_section',
      params: { accountId: '7', section: 'pabx' },
      query: { native_navigation: '1' },
    });
    expect(wrapper.find('[data-native-acw-alert]').exists()).toBe(false);
  });
  it('links a native synchronization error to its authorized integration without rendering raw errors or credentials', () => {
    const wrapper = render({
      cards: [{ key: 'integrations' }],
      provider: {
        configured: true,
        last_error: true,
        raw_error: 'SYNTHETIC_PRIVATE_ERROR',
      },
    });
    expect(wrapper.get('[data-native-provider-alert]').text()).toContain(
      'PENDING_ALERTS.SYNC_FAILED'
    );
    expect(
      wrapper.getComponent(RouterLinkStub).props('to').params.section
    ).toBe('integrations');
    expect(wrapper.text()).not.toContain('SYNTHETIC_PRIVATE_ERROR');
  });
  it('shows the exact scoped pending ACW count and its native destination only when authorized', () => {
    const wrapper = render({
      cards: [{ key: 'closures', count: 3 }],
      provider: { configured: true, last_error: false },
      capabilities: { supervise: true },
    });
    expect(wrapper.get('[data-native-acw-alert]').text()).toContain(
      'PENDING_ALERTS.PENDING_ACW 3'
    );
    expect(wrapper.getComponent(RouterLinkStub).props('to')).toEqual({
      name: 'jrc_contact_center_supervisor',
      params: { accountId: '7' },
      query: { native_navigation: '1' },
    });
    expect(wrapper.find('[data-native-provider-alert]').exists()).toBe(false);
  });
  it.each([undefined, null, 0, -1, '4', 1.5, NaN])(
    'does not fabricate pending counts from unauthorized or malformed values: %s',
    async count => {
      const wrapper = render({
        cards: [{ key: 'queues', count: 4 }],
        provider: {},
      });
      expect(
        wrapper.find('[data-administration-pending-alerts]').exists()
      ).toBe(false);
      await wrapper.setProps({
        context: { cards: [{ key: 'closures', count }], provider: {} },
      });
      expect(
        wrapper.find('[data-administration-pending-alerts]').exists()
      ).toBe(false);
    }
  );
  it('preserves an actual alert but never invents an unauthorized source navigation', () => {
    const wrapper = render({
      cards: [
        { key: 'queues' },
        { key: 'unknown_source' },
        { key: 'closures', count: 3 },
      ],
      capabilities: { supervise: false },
      provider: { configured: false },
    });
    expect(wrapper.get('[data-native-provider-alert]').exists()).toBe(true);
    expect(wrapper.findComponent(RouterLinkStub).exists()).toBe(false);
    expect(wrapper.get('[data-native-acw-alert]').text()).toContain(
      'PENDING_ACW 3'
    );
  });
  it('clears revoked sources and stale counters on a current-account or permission response change', async () => {
    const wrapper = render({
      cards: [{ key: 'closures', count: 3 }],
      provider: {},
    });
    await wrapper.setProps({
      accountId: '8',
      context: {
        cards: [{ key: 'integrations' }],
        provider: { configured: false },
      },
      query: {},
    });
    expect(wrapper.find('[data-native-acw-alert]').exists()).toBe(false);
    expect(wrapper.getComponent(RouterLinkStub).props('to')).toEqual({
      name: 'jrc_contact_center_admin_section',
      params: { accountId: '8', section: 'integrations' },
      query: {},
    });
    await wrapper.setProps({ context: { cards: [], provider: {} } });
    expect(wrapper.find('[data-administration-pending-alerts]').exists()).toBe(
      false
    );
  });
});
