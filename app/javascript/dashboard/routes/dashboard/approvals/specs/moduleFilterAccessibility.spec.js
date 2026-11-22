import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, reactive } from 'vue';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { approvalClient } from 'dashboard/api/approvals';
import english from 'dashboard/i18n/locale/en/jrcApprovals.json';
import portuguese from 'dashboard/i18n/locale/pt_BR/jrcApprovals.json';
import contactCenter from 'dashboard/i18n/locale/en/jrcContactCenter.json';
import ApprovalsPage from '../ApprovalsPage.vue';

const navigation = vi.hoisted(() => ({ route: null, push: vi.fn() }));
vi.mock('vue-router', () => ({
  useRoute: () => navigation.route,
  useRouter: () => ({
    push: navigation.push,
    resolve: () => ({ fullPath: '/SYNTHETIC-new-filter-location' }),
  }),
}));
vi.mock('dashboard/api/approvals', () => ({ approvalClient: vi.fn() }));
enableAutoUnmount(afterEach);
const Dialog = defineComponent({
  setup(_, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
    return () => null;
  },
});
const context = {
  account_id: 1,
  member_id: 9,
  scopes: [
    {
      issuer_company_id: 10,
      business_unit_id: 20,
      capabilities: ['request_create'],
    },
  ],
};
let api;
beforeEach(() => {
  vi.clearAllMocks();
  navigation.route = reactive({
    params: { accountId: '1', screen: 'inbox' },
    query: { box: 'requested' },
    fullPath: '/app/accounts/1/approvals/inbox?box=requested',
  });
  navigation.push.mockImplementation(destination => {
    navigation.route.params = destination.params;
    navigation.route.query = destination.query;
    navigation.route.fullPath = '/SYNTHETIC-filtered-module-location';
    return Promise.resolve();
  });
  const data = {
    context,
    'requests/summary': { pending: 0, approved: 0, rejected: 0, due_today: 0 },
    requests: [],
  };
  api = {
    get: vi.fn(path =>
      Promise.resolve({
        data: data[path],
        headers: { 'x-total-count': '0', 'x-page': '1', 'x-per-page': '25' },
      })
    ),
  };
  approvalClient.mockReturnValue(api);
});
const render = async (locale, component = ApprovalsPage) => {
  const store = createStore({
    getters: {
      getCurrentAccountId: () => 1,
      getCurrentUserID: () => 9,
      getCurrentRole: () => 'agent',
      getCurrentUser: () => ({
        id: 9,
        accounts: [{ id: 1, role: 'agent', custom_role_id: 5 }],
      }),
    },
  });
  const wrapper = mount(component, {
    global: {
      plugins: [
        store,
        createI18n({
          legacy: false,
          locale,
          fallbackLocale: 'en',
          messages: {
            en: { ...english, ...contactCenter },
            pt_BR: { ...portuguese, ...contactCenter },
          },
        }),
      ],
      stubs: { Dialog, Icon: true, RouterLink: true },
    },
  });
  await flushPromises();
  return wrapper;
};
const moduleFields = wrapper =>
  wrapper
    .findAll('select')
    .filter(select => select.find('option[value="contact_center"]').exists());

describe('Native approval module-filter accessible label', () => {
  it.each([
    ['pt_BR', 'Módulo'],
    ['en', 'Module'],
  ])(
    'associates the %s visible label without mixing dropdown option text and submits the actual scoped filter',
    async (locale, label) => {
      const wrapper = await render(locale);
      const fields = moduleFields(wrapper);
      expect(fields).toHaveLength(1);
      const field = fields[0];
      const reference = field.attributes('aria-labelledby');
      expect(reference).toBeTruthy();
      const visible = wrapper
        .findAll('[id]')
        .find(node => node.attributes('id') === reference);
      expect(visible.text()).toBe(label);
      expect(visible.text()).not.toContain('Call Center');
      await field.setValue('contact_center');
      await wrapper.get('form').trigger('submit');
      await flushPromises();
      expect(navigation.push).toHaveBeenCalledWith(
        expect.objectContaining({
          query: expect.objectContaining({
            module_key: 'contact_center',
            box: 'requested',
          }),
        })
      );
      expect(api.get).toHaveBeenCalledWith(
        'requests',
        expect.objectContaining({
          module_key: 'contact_center',
          requested_by_me: true,
        })
      );
    }
  );

  it('keeps labels unambiguous when two native page instances share an application', async () => {
    const Both = () => h('main', [h(ApprovalsPage), h(ApprovalsPage)]);
    const wrapper = await render('pt_BR', Both);
    const fields = moduleFields(wrapper);
    expect(fields).toHaveLength(2);
    const references = fields.map(field => field.attributes('aria-labelledby'));
    expect(references.every(Boolean)).toBe(true);
    expect(new Set(references).size).toBe(2);
  });
});
