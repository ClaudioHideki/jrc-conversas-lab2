import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { nextTick, reactive, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { routes } from '../routes';
import PabxNativePage from './PabxNativePage.vue';

const mocks = vi.hoisted(() => ({
  route: null,
  actor: null,
  replace: vi.fn(),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: mocks.replace }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => mocks.actor,
}));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { administration: vi.fn(), operationalHealth: vi.fn() },
}));
const administration = () => ({
  cards: [{ key: 'extensions' }, { key: 'queues' }],
  provider: { configured: false, last_sync_at: null, last_error: false },
  capabilities: { configuration_audit: false },
  native_links: { pabx_settings: false },
});
const health = (account = '1') => ({
  contract_version: 1,
  account_id: account,
  observed_at: '2026-11-27T12:30:00.000Z',
  queues: { active: 2, memberships: 3 },
  events: { statuses: { pending: 4, processed: 5 }, unverified: 1 },
  commands: { statuses: { requested: 6, accepted_by_gateway: 7 } },
});
let wrapper;
const render = async () => {
  wrapper = mount(PabxNativePage, {
    global: {
      stubs: {
        Icon: true,
        RouterLink: {
          name: 'RouterLink',
          props: ['to'],
          template: '<a><slot /></a>',
        },
        Button: {
          props: ['label', 'disabled', 'isLoading'],
          emits: ['click'],
          template:
            '<button :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });
  await flushPromises();
};
const metric = key =>
  wrapper.get(`[data-native-pabx-count="${key}"] dd`).text();
beforeEach(() => {
  mocks.route = reactive({
    params: { accountId: '1' },
    query: { preserved: 'yes' },
  });
  mocks.actor = ref({
    id: 7,
    type: 'User',
    accounts: [
      {
        id: 1,
        role: 'agent',
        custom_role_id: 3,
        permissions: ['jrc_contact_center_supervise'],
      },
    ],
  });
  mocks.replace.mockReset();
  API.administration.mockReset().mockResolvedValue({ data: administration() });
  API.operationalHealth.mockReset().mockResolvedValue({ data: health() });
});
afterEach(() => wrapper?.unmount());

it('uses only two native reads and renders the exact scoped local counts and observation time', async () => {
  await render();
  expect(API.administration).toHaveBeenCalledExactlyOnceWith('1');
  expect(API.operationalHealth).toHaveBeenCalledExactlyOnceWith('1');
  expect(['queues', 'memberships', 'events', 'commands'].map(metric)).toEqual([
    '2',
    '3',
    '9',
    '13',
  ]);
  expect(
    wrapper.get('[data-native-pabx-observed-at]').attributes('datetime')
  ).toBe(health().observed_at);
  expect(wrapper.text()).not.toMatch(/PABX Online|314|99[.,]9%/);
  expect(wrapper.find('[data-native-pabx-protected-settings]').exists()).toBe(
    false
  );
});
it('preserves a true empty native snapshot as zero without making up provider metrics', async () => {
  const data = health();
  data.queues = { active: 0, memberships: 0 };
  data.events = { statuses: {}, unverified: 0 };
  data.commands = { statuses: {} };
  API.operationalHealth.mockResolvedValue({ data });
  await render();
  expect(['queues', 'memberships', 'events', 'commands'].map(metric)).toEqual([
    '0',
    '0',
    '0',
    '0',
  ]);
  expect(wrapper.text()).toContain(
    'JRC_CONTACT_CENTER.NATIVE_PABX.INSTANT_SCOPE'
  );
});
it('displays loading without counters or zero and suppresses duplicate refresh while reads are pending', async () => {
  let resolve;
  API.operationalHealth.mockImplementationOnce(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  await render();
  expect(wrapper.find('[data-native-pabx-count]').exists()).toBe(false);
  expect(wrapper.get('button').attributes('disabled')).toBeDefined();
  await wrapper.get('button').trigger('click');
  expect(API.operationalHealth).toHaveBeenCalledTimes(1);
  resolve({ data: health() });
  await flushPromises();
  expect(metric('events')).toBe('9');
});
it('keeps successful configuration when health fails and omits raw upstream secrets', async () => {
  API.operationalHealth.mockRejectedValue(
    new Error('SYNTHETIC_PASSWORD internal.host 500')
  );
  await render();
  expect(wrapper.get('[data-native-pabx-configured]').text()).toContain(
    'CONNECTION_MISSING'
  );
  expect(
    wrapper.get('[data-native-pabx-observations] [role="alert"]').text()
  ).toContain('NATIVE_PABX.ERROR');
  expect(wrapper.text()).not.toMatch(/SYNTHETIC_PASSWORD|internal.host/);
  expect(wrapper.find('[data-native-pabx-count]').exists()).toBe(false);
});
it('preserves healthy scoped observations if the configuration read is denied', async () => {
  API.administration.mockRejectedValue({
    response: { status: 403, data: { secret: 'SYNTHETIC_HIDDEN' } },
  });
  await render();
  expect(
    wrapper.get('[data-native-pabx-configuration] [role="alert"]').text()
  ).toContain('NATIVE_PABX.DENIED');
  expect(metric('queues')).toBe('2');
  expect(wrapper.find('[data-native-pabx-resource]').exists()).toBe(false);
  expect(wrapper.text()).not.toContain('SYNTHETIC_HIDDEN');
});
it.each([
  { account_id: '2' },
  { contract_version: 2 },
  { queues: { active: -1, memberships: 3 } },
  { events: { statuses: { pending: '4' }, unverified: 1 } },
  { observed_at: 'invalid-time' },
])(
  'refuses a mismatching or malformed health response %j rather than borrowing another scope',
  async patch => {
    API.operationalHealth.mockResolvedValue({
      data: { ...health(), ...patch },
    });
    await render();
    expect(wrapper.find('[data-native-pabx-count]').exists()).toBe(false);
    expect(
      wrapper.get('[data-native-pabx-observations] [role="alert"]').text()
    ).toContain('NATIVE_PABX.ERROR');
  }
);
it('shows native gateway and PABX receipt states distinctly and keeps the external boundary visible', async () => {
  mocks.route.query.pabx_tab = 'diagnostic';
  const data = health();
  data.commands.statuses.confirmed_by_pabx = 2;
  API.operationalHealth.mockResolvedValue({ data });
  await render();
  expect(wrapper.text()).toContain('JRC_CONTACT_CENTER.NATIVE_PABX.GATEWAY');
  expect(wrapper.text()).toContain(
    'JRC_CONTACT_CENTER.NATIVE_PABX.CONFIRMATION'
  );
  expect(wrapper.get('[data-native-pabx-unverified]').text()).toContain(
    'NATIVE_PABX.UNVERIFIED'
  );
  expect(wrapper.get('[data-native-pabx-boundary]').text()).toContain(
    'NATIVE_PABX.BOUNDARY'
  );
});
it('shows only server-authorized native destinations and never infers superadmin settings from local role', async () => {
  mocks.actor.value.accounts[0].role = 'administrator';
  await render();
  const links = wrapper.findAllComponents({ name: 'RouterLink' });
  expect(links).toHaveLength(2);
  expect(links.map(link => link.props('to'))).toEqual(
    ['extensions', 'queues'].map(section => ({
      name: 'jrc_contact_center_admin_section',
      params: { accountId: '1', section },
      query: mocks.route.query,
    }))
  );
  expect(wrapper.find('[data-native-pabx-protected-settings]').exists()).toBe(
    false
  );
});
it('renders the existing protected settings and audit links only when the native API authorizes them', async () => {
  const data = administration();
  data.native_links.pabx_settings = true;
  data.capabilities.configuration_audit = true;
  API.administration.mockResolvedValue({ data });
  await render();
  expect(
    wrapper.getComponent('[data-native-pabx-protected-settings]').props('to')
  ).toEqual({ name: 'ramal_settings', params: { accountId: '1' } });
  expect(
    wrapper
      .findAllComponents({ name: 'RouterLink' })
      .some(link => link.props('to').params.section === 'audit')
  ).toBe(true);
});
it('preserves unrelated query state when changing tabs without triggering a provider action', async () => {
  await render();
  const nav = wrapper.get('nav');
  await nav.findAll('button')[1].trigger('click');
  expect(mocks.replace).toHaveBeenCalledWith({
    query: { preserved: 'yes', pabx_tab: 'sync' },
  });
  expect(API.administration).toHaveBeenCalledTimes(1);
  expect(API.operationalHealth).toHaveBeenCalledTimes(1);
});
it('shows the exact stored sync instant and a sanitized failure, without claiming provider success', async () => {
  mocks.route.query.pabx_tab = 'sync';
  const data = administration();
  data.provider.last_sync_at = health().observed_at;
  data.provider.last_error = true;
  API.administration.mockResolvedValue({ data });
  await render();
  expect(wrapper.get('[data-native-pabx-last-sync]').text()).toBe(
    health().observed_at
  );
  expect(wrapper.text()).toContain('JRC_CONTACT_CENTER.ADMIN.SYNC_ERROR');
  expect(wrapper.text()).toContain(
    'JRC_CONTACT_CENTER.NATIVE_PABX.NO_EXECUTION'
  );
});
it('refuses malformed configured synchronization time instead of displaying an invented empty state', async () => {
  const data = administration();
  data.provider.last_sync_at = 0;
  API.administration.mockResolvedValue({ data });
  await render();
  expect(
    wrapper.get('[data-native-pabx-configuration] [role="alert"]').text()
  ).toContain('NATIVE_PABX.ERROR');
  expect(wrapper.find('[data-native-pabx-configured]').exists()).toBe(false);
});
it('clears old data synchronously on a changed profile and ignores late responses from the former authority', async () => {
  await render();
  let resolve;
  API.operationalHealth.mockImplementationOnce(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  mocks.actor.value.accounts[0].custom_role_id = 9;
  await nextTick();
  expect(wrapper.find('[data-native-pabx-count]').exists()).toBe(false);
  await flushPromises();
  mocks.actor.value.id = 8;
  await flushPromises();
  expect(metric('queues')).toBe('2');
  resolve({ data: { ...health(), queues: { active: 99, memberships: 99 } } });
  await flushPromises();
  expect(metric('queues')).toBe('2');
  expect(wrapper.text()).not.toContain('99');
});
it('rechecks account identity and does not reuse a former-account payload', async () => {
  await render();
  mocks.route.params.accountId = '2';
  await flushPromises();
  expect(API.operationalHealth).toHaveBeenLastCalledWith('2');
  expect(wrapper.find('[data-native-pabx-count]').exists()).toBe(false);
  expect(
    wrapper.get('[data-native-pabx-observations] [role="alert"]').text()
  ).toContain('NATIVE_PABX.ERROR');
});
it('does not fetch data without an authenticated user and clears both old sources', async () => {
  await render();
  mocks.actor.value = null;
  await flushPromises();
  expect(API.operationalHealth).toHaveBeenCalledTimes(1);
  expect(API.administration).toHaveBeenCalledTimes(1);
  expect(wrapper.find('[data-native-pabx-count]').exists()).toBe(false);
  expect(wrapper.find('[data-native-pabx-resource]').exists()).toBe(false);
});
it('leaves presence-only refreshes outside the authorization epoch', async () => {
  await render();
  mocks.actor.value.accounts[0].availability_status = 'offline';
  await flushPromises();
  expect(API.operationalHealth).toHaveBeenCalledTimes(1);
});
it('keeps the same protected route and uses the new native page rather than the illustrative catalog', async () => {
  const route = routes[0].children.find(
    item => item.name === 'jrc_contact_center_pabx'
  );
  expect(route.meta.permissions).toEqual([
    'jrc_contact_center_supervise',
    'jrc_contact_center_configure',
  ]);
  expect(route.meta.featureFlag).toBe('jrc_contact_center');
  expect(route.props).toBeUndefined();
  expect((await route.component()).default).toBe(PabxNativePage);
});
