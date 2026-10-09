import { beforeEach, describe, expect, it, vi } from 'vitest';
import { flushPromises, mount } from '@vue/test-utils';
import { reactive } from 'vue';
import { createStore } from 'vuex';
import { routeLocationKey } from 'vue-router';
import { createI18n } from 'vue-i18n';
import Panel from '../NativeResourcesPanel.vue';
const mocks = vi.hoisted(() => ({
  session: null,
  list: vi.fn(),
  read: vi.fn(),
  create: vi.fn(),
  update: vi.fn(),
  archive: vi.fn(),
}));
vi.mock('dashboard/api/serviceDeskResources', () => ({ default: mocks }));
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => mocks.session,
}));
const context = () => ({
  account_id: '1',
  units: [{ id: '2' }],
  capabilities: { incidents: { index: true } },
});
const asset = () => ({
  id: '8',
  account_id: '1',
  unit_id: '2',
  resource_kind: 'asset',
  name: 'Router LAB',
  state: 'active',
  priority: 'normal',
  lock_version: 0,
  history: [],
  details: {},
  ticket_ids: [],
  permissions: { show: true, update: true, destroy: true },
});
const payload = items => ({
  contract_version: 1,
  account_id: '1',
  items,
  meta: { page: 1, per_page: 20, total: items.length },
});
const Button = {
  props: ['label', 'disabled', 'type'],
  template:
    '<button :type="type || \'button\'" :disabled="disabled">{{ label }}</button>',
};
const build = unitId =>
  mount(Panel, {
    props: { unitId, kind: 'asset' },
    global: {
      plugins: [
        createStore({
          getters: {
            'accounts/getAccount': () => () => ({ id: 1 }),
            'accounts/isFeatureEnabledonAccount': () => () => false,
            'globalConfig/isOnChatwootCloud': () => false,
            getCurrentRole: () => 'agent',
            getCurrentUser: () => ({ accounts: [{ id: 1, role: 'agent' }] }),
          },
        }),
        createI18n({
          legacy: false,
          locale: 'en',
          missingWarn: false,
          fallbackWarn: false,
        }),
      ],
      provide: { [routeLocationKey]: reactive({ params: { accountId: '1' } }) },
      stubs: { Button, Pagination: true, Lookup: true, State: true },
    },
  });
describe('Native resource UI uses persisted authorized readback', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.session = {
      state: reactive({ status: 'ready', context: context() }),
    };
    mocks.list.mockResolvedValue(payload([]));
    mocks.read.mockResolvedValue({ resource: asset() });
    mocks.create.mockResolvedValue({
      applied: true,
      account_id: '1',
      resource: { id: '8' },
    });
  });
  it('does not pick a first unit or call the API without an explicit unit', async () => {
    const wrapper = build('');
    await flushPromises();
    expect(mocks.list).not.toHaveBeenCalled();
    expect(wrapper.find('form').exists()).toBe(false);
    wrapper.unmount();
  });
  it('verifies a saved asset using GET before closing the edit form', async () => {
    const wrapper = build('2');
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text().includes('create_resource'))
      .trigger('click');
    await wrapper.find('input[required]').setValue('Router LAB');
    await wrapper.findAll('form')[1].trigger('submit');
    await flushPromises();
    expect(mocks.create).toHaveBeenCalledWith(
      '1',
      '2',
      expect.objectContaining({ name: 'Router LAB', resource_kind: 'asset' }),
      expect.any(String),
      expect.any(AbortSignal)
    );
    expect(mocks.read).toHaveBeenCalledWith('1', '8', expect.any(AbortSignal));
    expect(wrapper.find('input[required]').exists()).toBe(false);
    wrapper.unmount();
  });
  it('discards in-flight records and editing state after unit permission revocation', async () => {
    let resolve;
    mocks.list.mockReturnValue(
      new Promise(done => {
        resolve = done;
      })
    );
    const wrapper = build('2');
    await flushPromises();
    mocks.session.state.context = { ...context(), units: [] };
    await flushPromises();
    resolve(payload([asset()]));
    await flushPromises();
    expect(wrapper.text()).not.toContain('Router LAB');
    expect(wrapper.find('input[required]').exists()).toBe(false);
    wrapper.unmount();
  });
});
