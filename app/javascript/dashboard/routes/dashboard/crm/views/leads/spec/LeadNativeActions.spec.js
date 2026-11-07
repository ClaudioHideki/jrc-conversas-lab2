import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { reactive } from 'vue';
import { beforeEach, afterEach, it, expect, vi } from 'vitest';
import LeadsIndex from '../LeadsIndex.vue';
import leads from 'dashboard/store/crm/modules/leads';
import { leadsAPI, pipelinesAPI, productsAPI } from 'dashboard/api/crm';
import { useAlert } from 'dashboard/composables';

const navigation = vi.hoisted(() => ({
  route: null,
  router: { push: vi.fn(), replace: vi.fn() },
}));
vi.mock('vue-router', () => ({
  useRoute: () => navigation.route,
  useRouter: () => navigation.router,
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/layout/useQuickActionTarget', () => ({
  useQuickActionTarget: vi.fn(),
}));
vi.mock('dashboard/api/crm', () => ({
  leadsAPI: {
    list: vi.fn(),
    delete: vi.fn(),
    convert: vi.fn(),
    update: vi.fn(),
  },
  pipelinesAPI: { list: vi.fn() },
  productsAPI: { list: vi.fn() },
  stagesAPI: { list: vi.fn() },
}));
let wrapper;
let store;
let authority;
let records;
beforeEach(() => {
  vi.resetAllMocks();
  authority = reactive({
    account: 1,
    user: 7,
    role: 'administrator',
    grant: 1,
  });
  navigation.route = reactive({
    params: { accountId: '1' },
    query: { leadId: '1', customer_segment_id: '9', page: '2' },
  });
  records = [{ id: 1, name: 'Synthetic native lead', status: 'qualified' }];
  leadsAPI.list.mockImplementation(async () => ({
    data: structuredClone(records),
  }));
  leadsAPI.delete.mockImplementation(async id => {
    records = records.filter(record => record.id !== id);
    return { status: 204 };
  });
  pipelinesAPI.list.mockResolvedValue({ data: [] });
  productsAPI.list.mockResolvedValue({ data: [] });
  vi.spyOn(window, 'confirm').mockReturnValue(true);
  store = createStore({
    getters: {
      getCurrentAccountId: () => authority.account,
      getCurrentUserID: () => authority.user,
      getCurrentRole: () => authority.role,
      getCurrentUser: () => ({
        id: authority.user,
        accounts: [
          {
            id: authority.account,
            role: authority.role,
            custom_role_id: authority.grant,
          },
        ],
      }),
    },
    modules: {
      jrcCrm: {
        namespaced: true,
        modules: { leads: { ...leads, state: structuredClone(leads.state) } },
      },
    },
  });
});
afterEach(() => {
  wrapper?.unmount();
  vi.restoreAllMocks();
});
const render = async () => {
  wrapper = mount(LeadsIndex, {
    global: {
      plugins: [store],
      stubs: {
        Teleport: true,
        LeadCreateModal: true,
        LeadDetailModal: true,
        LeadConversionModal: true,
        CrmStatusBadge: true,
      },
    },
  });
  await flushPromises();
};

it('deletes through the actual Vuex module and native API while retaining the segment and navigation filters', async () => {
  await render();
  await wrapper.get('[title="Excluir lead"]').trigger('click');
  await flushPromises();
  expect(window.confirm).toHaveBeenCalledWith(
    expect.stringContaining('O contato continuará cadastrado')
  );
  expect(leadsAPI.delete).toHaveBeenCalledWith(1);
  expect(store.getters['jrcCrm/leads/allLeads']).toEqual([]);
  expect(leadsAPI.list).toHaveBeenLastCalledWith({
    search: '',
    status: '',
    customer_segment_id: '9',
  });
  expect(navigation.router.replace).toHaveBeenCalledWith({
    query: { customer_segment_id: '9', page: '2' },
  });
});

it('does not delete or change cached rows when the user cancels confirmation', async () => {
  window.confirm.mockReturnValue(false);
  await render();
  await wrapper.get('[title="Excluir lead"]').trigger('click');
  await flushPromises();
  expect(leadsAPI.delete).not.toHaveBeenCalled();
  expect(store.getters['jrcCrm/leads/allLeads']).toHaveLength(1);
});

it.each([403, 409])(
  'keeps native HTTP %s rejection visible without a success or optimistic removal',
  async status => {
    leadsAPI.delete.mockRejectedValue({
      response: { status, data: { error: 'Synthetic native deletion denied' } },
    });
    await render();
    await wrapper.get('[title="Excluir lead"]').trigger('click');
    await flushPromises();
    expect(leadsAPI.delete).toHaveBeenCalledTimes(1);
    expect(store.getters['jrcCrm/leads/allLeads']).toHaveLength(1);
    expect(useAlert).toHaveBeenLastCalledWith(
      'Synthetic native deletion denied'
    );
    expect(navigation.router.replace).not.toHaveBeenCalled();
  }
);

it('ignores an old deletion receipt after account replacement without repeating or rolling back the native command', async () => {
  let finish;
  leadsAPI.delete.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  await wrapper.get('[title="Excluir lead"]').trigger('click');
  authority.account = 2;
  navigation.route.params.accountId = '2';
  await flushPromises();
  const requests = leadsAPI.list.mock.calls.length;
  finish({ status: 204 });
  await flushPromises();
  expect(leadsAPI.list).toHaveBeenCalledTimes(requests);
  expect(useAlert).not.toHaveBeenCalled();
  expect(navigation.router.replace).not.toHaveBeenCalled();
  expect(leadsAPI.delete).toHaveBeenCalledTimes(1);
});

it('does not report a native deletion as success after the view is unmounted', async () => {
  let finish;
  leadsAPI.delete.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  await wrapper.get('[title="Excluir lead"]').trigger('click');
  wrapper.unmount();
  finish({ status: 204 });
  await flushPromises();
  expect(useAlert).not.toHaveBeenCalled();
  expect(navigation.router.replace).not.toHaveBeenCalled();
});

it('shows an unavailable native list and retries instead of claiming an empty successful result', async () => {
  leadsAPI.list.mockRejectedValueOnce({ response: { status: 403 } });
  await render();
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  expect(wrapper.text()).not.toContain('Nenhum lead encontrado.');
  await wrapper.find('[role="alert"] button').trigger('click');
  await flushPromises();
  expect(wrapper.text()).toContain('Synthetic native lead');
  expect(wrapper.find('[role="alert"]').exists()).toBe(false);
});

it('closes the old conversion popup after authority changes and ignores its late native conversion receipt', async () => {
  let finish;
  leadsAPI.convert.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'Converter em negócio')
    .trigger('click');
  const modal = wrapper.getComponent({ name: 'LeadConversionModal' });
  modal.vm.$emit('submit', { pipeline_id: 1, stage_id: 10 });
  authority.role = 'agent';
  await flushPromises();
  expect(wrapper.findComponent({ name: 'LeadConversionModal' }).exists()).toBe(
    false
  );
  finish({
    data: {
      lead: { id: 1, status: 'converted' },
      deal: { id: 11 },
      message: 'Synthetic obsolete success',
    },
  });
  await flushPromises();
  expect(navigation.router.push).not.toHaveBeenCalled();
  expect(useAlert).not.toHaveBeenCalled();
});

it('prevents another deletion while the confirmed command is still awaiting its native receipt', async () => {
  let finish;
  leadsAPI.delete.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  await wrapper.get('[title="Excluir lead"]').trigger('click');
  expect(
    wrapper.get('[title="Excluir lead"]').attributes('disabled')
  ).toBeDefined();
  await wrapper.get('[title="Excluir lead"]').trigger('click');
  expect(leadsAPI.delete).toHaveBeenCalledTimes(1);
  finish({ status: 204 });
  await flushPromises();
});

it('does not restore older private product options after a role-change refresh', async () => {
  let finish;
  productsAPI.list.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  productsAPI.list.mockResolvedValueOnce({
    data: [{ id: 2, name: 'Synthetic current product' }],
  });
  authority.role = 'agent';
  await flushPromises();
  finish({ data: [{ id: 1, name: 'Synthetic obsolete product' }] });
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'Converter em negócio')
    .trigger('click');
  expect(
    wrapper.getComponent({ name: 'LeadConversionModal' }).props('products')
  ).toEqual([{ id: 2, name: 'Synthetic current product' }]);
});

it('cannot replace freshly scoped rows with a late previous-role status change', async () => {
  let finish;
  leadsAPI.update.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  await wrapper.get('tbody select').setValue('discarded');
  records = [{ id: 1, name: 'Synthetic refreshed lead', status: 'in_contact' }];
  authority.role = 'agent';
  await flushPromises();
  finish({
    data: { id: 1, name: 'Synthetic obsolete response', status: 'discarded' },
  });
  await flushPromises();
  expect(store.getters['jrcCrm/leads/allLeads']).toEqual(records);
  expect(useAlert).not.toHaveBeenCalled();
});
