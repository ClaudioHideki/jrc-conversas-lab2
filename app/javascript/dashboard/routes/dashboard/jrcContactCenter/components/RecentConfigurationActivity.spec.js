import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, reactive, ref } from 'vue';
import {
  enableAutoUnmount,
  flushPromises,
  mount,
  RouterLinkStub as RouterLink,
} from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import RecentConfigurationActivity from './RecentConfigurationActivity.vue';
import ControlDeskPage from '../views/ControlDeskPage.vue';

const mocks = vi.hoisted(() => ({ route: null, user: null }));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => mocks.user,
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, parameters = {}) => [key, ...Object.values(parameters)].join(' '),
  }),
}));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    configurationAudits: vi.fn(),
    configurationAudit: vi.fn(),
    administration: vi.fn(),
  },
}));
const Dialog = defineComponent({
  emits: ['close'],
  setup(_props, { expose, emit }) {
    const visible = ref(false);
    expose({
      open: () => {
        visible.value = true;
      },
      close: () => {
        visible.value = false;
        emit('close');
      },
    });
    return { visible };
  },
  template:
    '<div v-if="visible" data-dialog><slot /><slot name="footer" /></div>',
});
const event = {
  id: 7,
  resource_type: 'queue',
  resource_id: 2,
  operation: 'update',
  created_at: '2026-11-18T12:00:00Z',
  actor_id: 4,
  actor_name: 'SYNTHETIC actor',
  correlation_id: 'SYNTHETIC correlation',
  revision: 2,
  before: { name: 'SYNTHETIC previous' },
  after: { name: 'SYNTHETIC current' },
  scopes: {
    before: { account_id: '1', unit_id: '10' },
    after: { account_id: '1', unit_id: '10' },
  },
  omitted_fields: [],
};
const response = (items = [event]) => ({
  data: {
    items,
    window: {
      from: '2026-10-20',
      to: '2026-11-18',
      timezone: 'America/Sao_Paulo',
    },
  },
});
const render = () =>
  mount(RecentConfigurationActivity, {
    props: { accountId: '1' },
    global: { stubs: { Dialog, RouterLink } },
  });
const pageData = configurationAudit => ({
  data: {
    cards: [],
    capabilities: { configuration_audit: configurationAudit },
    provider: {},
  },
});
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({
    params: { accountId: '1' },
    query: { native_navigation: '1' },
  });
  mocks.user = ref({
    id: 4,
    type: 'User',
    accounts: [
      {
        id: 1,
        role: 'administrator',
        status: 'active',
        custom_role_id: 2,
        permissions: ['jrc_contact_center_view', 'jrc_contact_center_audit'],
      },
    ],
  });
  API.configurationAudits.mockResolvedValue(response());
  API.configurationAudit.mockResolvedValue({
    data: { item: event, timezone: 'America/Sao_Paulo' },
  });
  API.administration.mockResolvedValue(pageData(true));
});

describe('recent native configuration activity', () => {
  it('uses the native ACW policy label and history identity without treating it as a queue', async () => {
    API.configurationAudits.mockResolvedValue(
      response([{ ...event, resource_type: 'acw_policy', resource_id: 1 }])
    );
    const wrapper = render();
    await flushPromises();
    expect(wrapper.get('[data-recent-event]').text()).toContain(
      'JRC_CONTACT_CENTER.ACW_OPERATION.POLICY_TITLE'
    );
    expect(wrapper.text()).not.toContain(
      'JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.QUEUE'
    );
  });

  it('requests five authorized records and shows the real window, timezone and actor', async () => {
    const wrapper = render();
    await flushPromises();
    expect(API.configurationAudits).toHaveBeenCalledWith('1', {
      page: '1',
      per_page: 5,
    });
    expect(wrapper.findAll('[data-recent-event]')).toHaveLength(1);
    expect(wrapper.text()).toContain('09:00');
    expect(wrapper.text()).toContain('20/10/2026');
    expect(wrapper.text()).toContain('America/Sao_Paulo');
    expect(wrapper.text()).toContain('SYNTHETIC actor');
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.LOCAL_ONLY'
    );
  });

  it('opens fresh native details and closes through the explicit footer', async () => {
    const wrapper = render();
    await flushPromises();
    await wrapper.get('[data-recent-event]').trigger('click');
    await flushPromises();
    expect(API.configurationAudit).toHaveBeenCalledWith('1', 7);
    expect(wrapper.get('[data-dialog]').text()).toContain('SYNTHETIC previous');
    expect(wrapper.get('[data-dialog]').text()).toContain('SYNTHETIC current');
    await wrapper.get('[data-recent-close]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-dialog]').exists()).toBe(false);
  });

  it('keeps navigation context while clearing stale audit filters and opening exact resource history', async () => {
    mocks.route.query.audit_config_actor_id = '999';
    mocks.route.query.audit_config_from = '2026-01-01';
    const wrapper = render();
    await flushPromises();
    expect(wrapper.findComponent('[data-recent-all]').props('to')).toEqual({
      name: 'jrc_contact_center_admin_section',
      params: { accountId: '1', section: 'audit' },
      query: { native_navigation: '1', audit_source: 'configuration' },
    });
    await wrapper.get('[data-recent-event]').trigger('click');
    await flushPromises();
    expect(
      wrapper.findComponent('[data-recent-history]').props('to').query
    ).toEqual({
      native_navigation: '1',
      audit_source: 'configuration',
      audit_config_history: 'true',
      audit_config_resource_type: 'queue',
      audit_config_resource_id: '2',
    });
  });

  it('distinguishes a failed read from a genuinely empty period and allows an explicit retry', async () => {
    API.configurationAudits.mockRejectedValueOnce(
      new Error('SYNTHETIC offline')
    );
    const wrapper = render();
    await flushPromises();
    expect(wrapper.get('[role=alert]').text()).toBe(
      'JRC_CONTACT_CENTER.COMMON.ERROR'
    );
    expect(wrapper.text()).not.toContain(
      'JRC_CONTACT_CENTER.RECENT_ACTIVITY.EMPTY'
    );
    await wrapper.get('[data-recent-refresh]').trigger('click');
    await flushPromises();
    expect(wrapper.findAll('[data-recent-event]')).toHaveLength(1);
    expect(wrapper.find('[role=alert]').exists()).toBe(false);
  });

  it('clears the list and history after denied detail access instead of showing an empty-data success', async () => {
    API.configurationAudit.mockRejectedValueOnce({ response: { status: 403 } });
    const wrapper = render();
    await flushPromises();
    await wrapper.get('[data-recent-event]').trigger('click');
    await flushPromises();
    expect(wrapper.findAll('[data-recent-event]')).toHaveLength(0);
    expect(wrapper.text()).toContain('JRC_CONTACT_CENTER.ADMIN.DENIED');
    expect(wrapper.text()).not.toContain(
      'JRC_CONTACT_CENTER.RECENT_ACTIVITY.EMPTY'
    );
    expect(wrapper.find('[data-recent-history]').exists()).toBe(false);
  });

  it('does not reopen a popup or disclose a late detail response after closing it', async () => {
    let finish;
    API.configurationAudit.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = render();
    await flushPromises();
    await wrapper.get('[data-recent-event]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-recent-close]').trigger('click');
    finish({ data: { item: event, timezone: 'America/Sao_Paulo' } });
    await flushPromises();
    expect(wrapper.find('[data-dialog]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('SYNTHETIC previous');
  });

  it('does not reuse a pending list from another account', async () => {
    let finish;
    API.configurationAudits
      .mockImplementationOnce(
        () =>
          new Promise(resolve => {
            finish = resolve;
          })
      )
      .mockResolvedValueOnce(
        response([{ ...event, id: 8, actor_name: 'SYNTHETIC account 2' }])
      );
    const wrapper = render();
    await wrapper.setProps({ accountId: '2' });
    await flushPromises();
    finish(response());
    await flushPromises();
    expect(wrapper.find('[data-recent-event="7"]').exists()).toBe(false);
    expect(wrapper.text()).toContain('SYNTHETIC account 2');
    expect(wrapper.text()).not.toContain('SYNTHETIC actor');
  });

  it('shows a real empty period without manufacturing activity', async () => {
    API.configurationAudits.mockResolvedValueOnce(response([]));
    const wrapper = render();
    await flushPromises();
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.RECENT_ACTIVITY.EMPTY'
    );
    expect(wrapper.findAll('[data-recent-event]')).toHaveLength(0);
    expect(wrapper.find('[role=alert]').exists()).toBe(false);
  });
});

describe('Control Desk authenticated authority boundary', () => {
  const page = () =>
    mount(ControlDeskPage, { global: { stubs: { Dialog, RouterLink } } });

  it('does not fetch recent administrative data without the native capability', async () => {
    API.administration.mockResolvedValueOnce(pageData(false));
    const wrapper = page();
    await flushPromises();
    expect(wrapper.find('[data-recent-configuration]').exists()).toBe(false);
    expect(API.configurationAudits).not.toHaveBeenCalled();
  });

  it('clears an open private detail when the profile changes within the same account', async () => {
    const wrapper = page();
    await flushPromises();
    await wrapper.get('[data-recent-event]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('SYNTHETIC previous');
    API.administration.mockResolvedValueOnce(pageData(false));
    mocks.user.value.accounts[0].custom_role_id = 9;
    mocks.user.value.accounts[0].permissions = ['jrc_contact_center_view'];
    await flushPromises();
    expect(wrapper.find('[data-recent-configuration]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('SYNTHETIC previous');
    expect(API.administration).toHaveBeenCalledTimes(2);
  });

  it('does not mount an old privileged administration response after a profile change', async () => {
    let finish;
    API.administration.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = page();
    await flushPromises();
    API.administration.mockResolvedValueOnce(pageData(false));
    mocks.user.value.accounts[0].custom_role_id = 9;
    mocks.user.value.accounts[0].permissions = ['jrc_contact_center_view'];
    await flushPromises();
    finish(pageData(true));
    await flushPromises();
    expect(wrapper.find('[data-recent-configuration]').exists()).toBe(false);
    expect(API.configurationAudits).not.toHaveBeenCalled();
    expect(API.administration).toHaveBeenCalledTimes(2);
  });

  it('keeps private details cleared when server authorization rejects the refreshed profile', async () => {
    const wrapper = page();
    await flushPromises();
    await wrapper.get('[data-recent-event]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('SYNTHETIC previous');
    API.administration.mockRejectedValueOnce({ response: { status: 401 } });
    mocks.user.value.accounts[0].permissions = [];
    await flushPromises();
    expect(wrapper.find('[data-recent-configuration]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('SYNTHETIC previous');
    expect(wrapper.get('[role=alert]').text()).toBe(
      'JRC_CONTACT_CENTER.COMMON.ERROR'
    );
    expect(API.administration).toHaveBeenCalledTimes(2);
  });

  it('invalidates details on account status changes even when role permissions are unchanged', async () => {
    const wrapper = page();
    await flushPromises();
    await wrapper.get('[data-recent-event]').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('SYNTHETIC previous');
    API.administration.mockRejectedValueOnce({ response: { status: 401 } });
    mocks.user.value.accounts[0].status = 'inactive';
    await flushPromises();
    expect(wrapper.find('[data-recent-configuration]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('SYNTHETIC previous');
    expect(API.administration).toHaveBeenCalledTimes(2);
  });

  it('preserves an open detail when only native presence metadata changes', async () => {
    const wrapper = page();
    await flushPromises();
    await wrapper.get('[data-recent-event]').trigger('click');
    await flushPromises();
    mocks.user.value.accounts[0].availability_status = 'offline';
    mocks.user.value.accounts[0].active_at = '2026-11-18T12:01:00Z';
    await flushPromises();
    expect(wrapper.get('[data-dialog]').text()).toContain('SYNTHETIC previous');
    expect(API.administration).toHaveBeenCalledTimes(1);
  });

  it('clears administrative data when the authenticated user disappears', async () => {
    const wrapper = page();
    await flushPromises();
    expect(wrapper.find('[data-recent-configuration]').exists()).toBe(true);
    mocks.user.value = null;
    await flushPromises();
    expect(wrapper.find('[data-recent-configuration]').exists()).toBe(false);
    expect(wrapper.find('[data-card]').exists()).toBe(false);
    expect(API.administration).toHaveBeenCalledTimes(1);
  });
});
