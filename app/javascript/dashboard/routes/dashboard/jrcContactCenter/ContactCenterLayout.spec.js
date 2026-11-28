import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { reactive, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import ContactCenterLayout from './ContactCenterLayout.vue';

const mocks = vi.hoisted(() => ({ route: null, actor: null }));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => mocks.actor,
}));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { context: vi.fn() },
}));
const response = (capabilities = {}) => ({ data: { capabilities } });
const render = () =>
  mount(ContactCenterLayout, {
    global: {
      stubs: {
        Icon: true,
        RouterLink: {
          props: ['to'],
          template: '<a :data-route="to.name"><slot /></a>',
        },
        RouterView: {
          template:
            '<section data-native-child><input data-unsaved-child /></section>',
        },
      },
    },
  });
const links = wrapper =>
  wrapper.findAll('[data-route]').map(row => row.attributes('data-route'));
enableAutoUnmount(afterEach);
beforeEach(() => {
  mocks.route = reactive({
    params: { accountId: '1' },
    name: 'jrc_contact_center_cockpit',
  });
  mocks.actor = ref({
    id: 4,
    type: 'User',
    accounts: [1, 2].map(id => ({
      id,
      role: 'administrator',
      custom_role_id: 7,
      permissions: ['jrc_contact_center_view'],
      contact_center_eligible: true,
    })),
  });
  API.context.mockReset().mockResolvedValue(response());
});

it('uses fresh native capabilities and does not infer management from an administrator label', async () => {
  const wrapper = render();
  await flushPromises();
  expect(API.context).toHaveBeenCalledWith('1');
  expect(links(wrapper)).toContain('jrc_contact_center_cockpit');
  expect(links(wrapper)).not.toContain('jrc_contact_center_pabx');
  expect(links(wrapper)).not.toContain('jrc_contact_center_supervisor');
  expect(links(wrapper)).not.toContain('jrc_contact_center_settings');
});
it('exposes only the destinations explicitly authorized by the native response', async () => {
  API.context.mockResolvedValue(
    response({
      supervise: true,
      configure: true,
      reports: true,
      recordings_view: true,
    })
  );
  const wrapper = render();
  await flushPromises();
  expect(links(wrapper)).toEqual(
    expect.arrayContaining([
      'jrc_contact_center_pabx',
      'jrc_contact_center_supervisor',
      'jrc_contact_center_settings',
      'jrc_contact_center_reports',
      'jrc_contact_center_recordings',
    ])
  );
});
it('does not treat truthy strings as granted capabilities', async () => {
  API.context.mockResolvedValue(
    response({ configure: 'true', supervise: 1, reports: 'true' })
  );
  const wrapper = render();
  await flushPromises();
  expect(links(wrapper)).not.toContain('jrc_contact_center_pabx');
  expect(links(wrapper)).not.toContain('jrc_contact_center_reports');
});
it('clears the old navigation and mounted child before a same-account actor refresh completes', async () => {
  API.context.mockResolvedValueOnce(response({ configure: true }));
  const wrapper = render();
  await flushPromises();
  await wrapper.get('[data-unsaved-child]').setValue('SYNTHETIC private draft');
  let resolve;
  API.context.mockImplementationOnce(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  mocks.actor.value.id = 8;
  await flushPromises();
  expect(wrapper.find('[data-native-child]').exists()).toBe(false);
  expect(links(wrapper)).toEqual([]);
  resolve(response({ reports: true }));
  await flushPromises();
  expect(links(wrapper)).not.toContain('jrc_contact_center_pabx');
  expect(links(wrapper)).toContain('jrc_contact_center_reports');
  expect(wrapper.get('[data-unsaved-child]').element.value).toBe('');
});
it('refreshes eligibility changes and removes the previous authorized navigation on denial', async () => {
  API.context.mockResolvedValueOnce(response({ configure: true }));
  const wrapper = render();
  await flushPromises();
  API.context.mockRejectedValueOnce({ response: { status: 401 } });
  mocks.actor.value.accounts[0].contact_center_eligible = false;
  await flushPromises();
  expect(API.context).toHaveBeenCalledTimes(2);
  expect(links(wrapper)).toEqual([]);
  expect(wrapper.get('[role="alert"]').text()).toContain('COMMON.ERROR');
});
it('refreshes an in-place native permission change without reusing the old destinations', async () => {
  API.context.mockResolvedValueOnce(response({ supervise: true }));
  const wrapper = render();
  await flushPromises();
  mocks.actor.value.accounts[0].permissions.push('jrc_contact_center_reports');
  await flushPromises();
  expect(API.context).toHaveBeenCalledTimes(2);
  expect(links(wrapper)).not.toContain('jrc_contact_center_supervisor');
});
it('uses the new account and ignores a late successful response from the previous one', async () => {
  let resolve;
  API.context.mockImplementationOnce(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  const wrapper = render();
  mocks.route.params.accountId = '2';
  await flushPromises();
  resolve(response({ configure: true, supervise: true }));
  await flushPromises();
  expect(API.context).toHaveBeenLastCalledWith('2');
  expect(links(wrapper)).not.toContain('jrc_contact_center_pabx');
});
it('does not revive an old success after a later current-profile denial', async () => {
  let resolve;
  API.context.mockImplementationOnce(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  const wrapper = render();
  API.context.mockRejectedValueOnce({ response: { status: 401 } });
  mocks.actor.value.accounts[0].custom_role_id = 9;
  await flushPromises();
  resolve(response({ configure: true }));
  await flushPromises();
  expect(links(wrapper)).toEqual([]);
  expect(wrapper.find('[data-native-child]').exists()).toBe(false);
});
it('keeps the mounted user draft on a presence-only native membership refresh', async () => {
  const wrapper = render();
  await flushPromises();
  await wrapper
    .get('[data-unsaved-child]')
    .setValue('SYNTHETIC retained draft');
  Object.assign(mocks.actor.value.accounts[0], {
    availability: 'busy',
    active_at: '2026-11-27T12:00:00Z',
  });
  await flushPromises();
  expect(API.context).toHaveBeenCalledTimes(1);
  expect(wrapper.get('[data-unsaved-child]').element.value).toBe(
    'SYNTHETIC retained draft'
  );
});
it('clears authenticated data and does not issue a context request after logout', async () => {
  API.context.mockResolvedValueOnce(response({ configure: true }));
  const wrapper = render();
  await flushPromises();
  mocks.actor.value = null;
  await flushPromises();
  expect(API.context).toHaveBeenCalledTimes(1);
  expect(links(wrapper)).toEqual([]);
  expect(wrapper.find('[data-native-child]').exists()).toBe(false);
});

it.each([
  { recordings_view: true },
  { recordings_listen: true },
  { configure: true, reports: true },
  { recordings_view: true, recordings_listen: 'true' },
])(
  'requires both recording capabilities without inferring administrator rights: %j',
  async capabilities => {
    API.context.mockResolvedValueOnce(response(capabilities));
    const wrapper = render();
    await flushPromises();
    expect(
      wrapper.find('[data-contact-center-destination="quality"]').exists()
    ).toBe(false);
  }
);
it('links to the existing authorized recording page and quality query rather than a parallel route', async () => {
  API.context.mockResolvedValueOnce(
    response({ recordings_view: true, recordings_listen: true })
  );
  const wrapper = render();
  await flushPromises();
  const target = wrapper.getComponent(
    '[data-contact-center-destination="quality"]'
  );
  expect(target.props('to')).toEqual({
    name: 'jrc_contact_center_recordings',
    params: { accountId: '1' },
    query: { recordings_mode: 'quality' },
  });
  expect(
    wrapper.findAll('[data-contact-center-destination="quality"]')
  ).toHaveLength(1);
});
it('identifies the active recording mode without marking both same-route links as the current page', async () => {
  API.context.mockResolvedValueOnce(
    response({ recordings_view: true, recordings_listen: true })
  );
  mocks.route.name = 'jrc_contact_center_recordings';
  mocks.route.query = { recordings_mode: 'quality' };
  const wrapper = render();
  await flushPromises();
  const current = key =>
    wrapper
      .get(`[data-contact-center-destination="${key}"]`)
      .attributes('aria-current-value');
  expect(current('quality')).toBe('page');
  expect(current('jrc_contact_center_recordings')).toBe('false');
  mocks.route.query = {};
  await flushPromises();
  expect(current('quality')).toBe('false');
  expect(current('jrc_contact_center_recordings')).toBe('page');
});
it('closes the native mobile navigation after choosing the sentiment shortcut', async () => {
  API.context.mockResolvedValueOnce(
    response({ recordings_view: true, recordings_listen: true })
  );
  const wrapper = render();
  await flushPromises();
  const menu = wrapper.get('button[aria-expanded]');
  await menu.trigger('click');
  expect(menu.attributes('aria-expanded')).toBe('true');
  await wrapper
    .get('[data-contact-center-destination="quality"]')
    .trigger('click');
  expect(menu.attributes('aria-expanded')).toBe('false');
  expect(API.context).toHaveBeenCalledTimes(1);
});
