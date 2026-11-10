import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { createStore } from 'vuex';
import { beforeEach, afterEach, it, expect, vi } from 'vitest';
import ActivitiesIndex from '../ActivitiesIndex.vue';
import activities from 'dashboard/store/crm/modules/activities';
import deals from 'dashboard/store/crm/modules/deals';
import { activitiesAPI, dealsAPI } from 'dashboard/api/crm';
import { useAlert } from 'dashboard/composables';
import { draftKey, readDraft } from '../../../helpers/formDrafts';

const navigation = vi.hoisted(() => ({
  route: null,
  router: { push: vi.fn() },
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
  activitiesAPI: { list: vi.fn(), create: vi.fn(), complete: vi.fn() },
  dealsAPI: { list: vi.fn() },
}));
let wrapper;
let authority;
let store;
const ownerKey = draftKey(1, 7, 'crm:new_activity');
beforeEach(() => {
  vi.resetAllMocks();
  sessionStorage.clear();
  authority = reactive({
    account: 1,
    user: 7,
    role: 'administrator',
    grant: 1,
  });
  navigation.route = reactive({
    params: { accountId: '1' },
    query: { customer_segment_id: '9' },
  });
  activitiesAPI.list.mockResolvedValue({
    data: [
      {
        id: 1,
        title: 'Synthetic native activity',
        status: 'open',
        activity_type: 'call',
        due_at: '2026-11-07T12:00:00Z',
      },
    ],
  });
  dealsAPI.list.mockResolvedValue({
    data: [{ id: 10, title: 'Synthetic scoped deal' }],
  });
  activitiesAPI.create.mockResolvedValue({ data: { id: 2 } });
  activitiesAPI.complete.mockResolvedValue({ data: { id: 1 } });
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
        modules: {
          activities: {
            ...activities,
            state: structuredClone(activities.state),
          },
          deals: { ...deals, state: structuredClone(deals.state) },
        },
      },
    },
  });
});
afterEach(() => wrapper?.unmount());
const render = async () => {
  wrapper = mount(ActivitiesIndex, {
    global: {
      plugins: [store],
      stubs: {
        Teleport: true,
        RouterLink: true,
        AgendaRecord: true,
        ActivityEditDialog: true,
      },
    },
  });
  await flushPromises();
};
const openCreation = async () => {
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'Nova atividade')
    .trigger('click');
  const form = wrapper
    .findAll('form')
    .find(row => row.find('input[type="datetime-local"]').exists());
  await form.findAll('select')[0].setValue('10');
  await form
    .get('input[placeholder="Título"]')
    .setValue('Synthetic activity draft');
  await form.get('input[type="datetime-local"]').setValue('2026-11-09T10:30');
  return form;
};

it('closes the old creation form on role replacement while keeping its original owner draft', async () => {
  await render();
  await openCreation();
  authority.role = 'agent';
  await flushPromises();
  expect(wrapper.find('input[type="datetime-local"]').exists()).toBe(false);
  expect(readDraft(ownerKey).title).toBe('Synthetic activity draft');
  expect(activitiesAPI.create).not.toHaveBeenCalled();
});

it('does not restore obsolete related deal options after a replacement actor finishes initialization', async () => {
  let finish;
  dealsAPI.list.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  dealsAPI.list.mockResolvedValueOnce({
    data: [{ id: 20, title: 'Synthetic new actor deal' }],
  });
  authority.user = 99;
  await flushPromises();
  finish({ data: [{ id: 10, title: 'Synthetic obsolete actor deal' }] });
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'Nova atividade')
    .trigger('click');
  expect(wrapper.text()).toContain('Synthetic new actor deal');
  expect(wrapper.text()).not.toContain('Synthetic obsolete actor deal');
});

it('ignores an old creation receipt after grant replacement without clearing the original draft or navigating', async () => {
  let finish;
  activitiesAPI.create.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  const form = await openCreation();
  await form.trigger('submit');
  authority.grant = 2;
  await flushPromises();
  const requests = activitiesAPI.list.mock.calls.length;
  finish({ data: { id: 2 } });
  await flushPromises();
  expect(activitiesAPI.list).toHaveBeenCalledTimes(requests);
  expect(useAlert).not.toHaveBeenCalled();
  expect(navigation.router.push).not.toHaveBeenCalled();
  expect(readDraft(ownerKey).title).toBe('Synthetic activity draft');
});

it('does not navigate or clear the owner draft after unmount while native creation finishes', async () => {
  let finish;
  activitiesAPI.create.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  const form = await openCreation();
  await form.trigger('submit');
  wrapper.unmount();
  finish({ data: { id: 2 } });
  await flushPromises();
  expect(useAlert).not.toHaveBeenCalled();
  expect(navigation.router.push).not.toHaveBeenCalled();
  expect(readDraft(ownerKey).title).toBe('Synthetic activity draft');
});

it('does not submit the same activity creation twice while its first receipt is pending', async () => {
  let finish;
  activitiesAPI.create.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  const form = await openCreation();
  await form.trigger('submit');
  await form.trigger('submit');
  expect(activitiesAPI.create).toHaveBeenCalledTimes(1);
  finish({ data: { id: 2 } });
  await flushPromises();
});

it('prevents closing and replacing a draft while its creation receipt is pending', async () => {
  let finish;
  activitiesAPI.create.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  const form = await openCreation();
  await form.trigger('submit');
  await form
    .findAll('button')
    .find(button => button.text() === 'Cancelar')
    .trigger('click');
  expect(wrapper.find('input[type="datetime-local"]').exists()).toBe(true);
  finish({ data: { id: 2 } });
  await flushPromises();
});

it('ignores a completion receipt for an account that has been replaced', async () => {
  let finish;
  activitiesAPI.complete.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  await wrapper.get('tbody button[title="Concluir"]').trigger('click');
  authority.account = 2;
  navigation.route.params.accountId = '2';
  await flushPromises();
  const requests = activitiesAPI.list.mock.calls.length;
  finish({ data: { id: 1 } });
  await flushPromises();
  expect(activitiesAPI.list).toHaveBeenCalledTimes(requests);
  expect(activitiesAPI.complete).toHaveBeenCalledTimes(1);
  expect(useAlert).not.toHaveBeenCalled();
});

it('preserves the native creation fields, current segment and calendar destination after a current successful receipt', async () => {
  await render();
  const form = await openCreation();
  await form.trigger('submit');
  await flushPromises();
  expect(activitiesAPI.create).toHaveBeenCalledWith({
    activity: {
      deal_id: 10,
      activity_type: 'follow_up',
      title: 'Synthetic activity draft',
      due_at: '2026-11-09T10:30',
    },
  });
  expect(activitiesAPI.list).toHaveBeenLastCalledWith({
    customer_segment_id: '9',
  });
  expect(navigation.router.push).toHaveBeenCalledWith({
    name: 'crm_calendar',
    query: { date: '2026-11-09T10:30' },
  });
  expect(readDraft(ownerKey)).toBeNull();
});

it('prevents another native completion while the first receipt is pending', async () => {
  let finish;
  activitiesAPI.complete.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  await wrapper.get('tbody button[title="Concluir"]').trigger('click');
  expect(
    wrapper.get('tbody button[title="Concluir"]').attributes('disabled')
  ).toBeDefined();
  await wrapper.get('tbody button[title="Concluir"]').trigger('click');
  expect(activitiesAPI.complete).toHaveBeenCalledTimes(1);
  finish({ data: { id: 1 } });
  await flushPromises();
});

it('shows related deal denial and reloads current options through the existing retry action', async () => {
  dealsAPI.list.mockRejectedValueOnce({ response: { status: 403 } });
  await render();
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  await wrapper.find('[role="alert"] button').trigger('click');
  await flushPromises();
  expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  await openCreation();
  expect(wrapper.text()).toContain('Synthetic scoped deal');
});
