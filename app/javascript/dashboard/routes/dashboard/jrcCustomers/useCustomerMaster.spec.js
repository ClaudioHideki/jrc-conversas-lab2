import { computed, defineComponent } from 'vue';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createRouter, createMemoryHistory } from 'vue-router';
import { useCustomerMaster } from './useCustomerMaster';

const Harness = defineComponent({
  setup() {
    const master = useCustomerMaster();
    return {
      ...master,
      destination: computed(() =>
        master.accountScopedRoute('jrc_customer_company', { companyId: 42 })
      ),
    };
  },
  template: '<span>{{ enabled }} {{ canAccess }} {{ canAdmin }}</span>',
});

describe('Cadastro Mestre account and feature boundaries', () => {
  let store;
  let router;
  let wrapper;

  beforeEach(async () => {
    store = createStore({
      state: {
        enabled: false,
        role: 'administrator',
        user: { accounts: [{ id: 1, role: 'administrator' }] },
      },
      getters: {
        'accounts/isFeatureEnabledonAccount': state => (accountId, flag) =>
          accountId === 1 && flag === 'jrc_customer_master' && state.enabled,
        'accounts/getAccount': () => () => ({ id: 1 }),
        'globalConfig/isOnChatwootCloud': () => false,
        getCurrentRole: state => state.role,
        getCurrentUser: state => state.user,
      },
    });
    router = createRouter({
      history: createMemoryHistory(),
      routes: [
        {
          path: '/app/accounts/:accountId/dashboard',
          component: { template: '<div />' },
        },
      ],
    });
    await router.push('/app/accounts/1/dashboard');
    wrapper = mount(Harness, { global: { plugins: [store, router] } });
  });

  afterEach(() => wrapper.unmount());

  it('keeps all master access disabled when the account feature is off', () => {
    expect(wrapper.vm.enabled).toBe(false);
    expect(wrapper.vm.canAccess).toBe(false);
    expect(wrapper.vm.canAdmin).toBe(false);
  });

  it('uses the native account and company IDs after an administrator enables the feature', () => {
    store.state.enabled = true;
    expect(wrapper.vm.enabled).toBe(true);
    expect(wrapper.vm.canAccess).toBe(true);
    expect(wrapper.vm.canAdmin).toBe(true);
    expect(wrapper.vm.destination).toEqual({
      name: 'jrc_customer_company',
      params: { accountId: 1, companyId: 42 },
      query: {},
    });
  });

  it('requires contact permission for a custom role and keeps administration restricted', () => {
    store.state.enabled = true;
    store.state.role = 'agent';
    store.state.user.accounts = [
      { id: 1, role: 'agent', custom_role_id: 3, permissions: [] },
    ];
    expect(wrapper.vm.canAccess).toBe(false);
    store.state.user.accounts[0].permissions.push('contact_manage');
    expect(wrapper.vm.canAccess).toBe(true);
    expect(wrapper.vm.canAdmin).toBe(false);
  });

  it('rechecks the account boundary when navigation changes to another tenant', async () => {
    store.state.enabled = true;
    expect(wrapper.vm.canAccess).toBe(true);
    await router.push('/app/accounts/2/dashboard');
    expect(wrapper.vm.accountId).toBe(2);
    expect(wrapper.vm.enabled).toBe(false);
    expect(wrapper.vm.canAccess).toBe(false);
  });
});
