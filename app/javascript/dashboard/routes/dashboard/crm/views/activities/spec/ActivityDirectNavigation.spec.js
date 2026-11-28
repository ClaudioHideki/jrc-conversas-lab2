import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { reactive } from 'vue';
import { createStore } from 'vuex';
import {
  enableAutoUnmount,
  flushPromises,
  shallowMount,
} from '@vue/test-utils';
import { activitiesAPI, dealsAPI } from 'dashboard/api/crm';
import ActivitiesIndex from '../ActivitiesIndex.vue';

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
  activitiesAPI: { create: vi.fn(), complete: vi.fn() },
  dealsAPI: { list: vi.fn() },
}));
let authority;
let store;
const render = async () => {
  const wrapper = shallowMount(ActivitiesIndex, {
    global: {
      plugins: [store],
      stubs: { RouterLink: true, AgendaRecord: true, ActivityEditDialog: true },
    },
  });
  await flushPromises();
  return wrapper;
};
const editor = wrapper => wrapper.findComponent({ name: 'ActivityEditDialog' });
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.resetAllMocks();
  sessionStorage.clear();
  authority = reactive({ account: 1, user: 7, role: 'agent', grant: 4 });
  navigation.route = reactive({
    params: { accountId: '1' },
    query: { activityId: '445', customer_segment_id: '9' },
  });
  navigation.router.replace.mockImplementation(({ query }) => {
    navigation.route.query = query;
    return Promise.resolve();
  });
  dealsAPI.list.mockResolvedValue({ data: [] });
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
      'jrcCrm/activities/allActivities': () => [],
    },
  });
  store.dispatch = vi.fn().mockResolvedValue();
});

it('opens the existing account-authorized dialog even outside the list and clears only the consumed link when closed', async () => {
  const wrapper = await render();
  expect(editor(wrapper).props('activityId')).toBe(445);
  expect(store.getters['jrcCrm/activities/allActivities']).toEqual([]);
  expect(activitiesAPI.create).not.toHaveBeenCalled();
  expect(activitiesAPI.complete).not.toHaveBeenCalled();
  editor(wrapper).vm.$emit('close');
  await flushPromises();
  expect(editor(wrapper).exists()).toBe(false);
  expect(navigation.router.replace).toHaveBeenCalledWith({
    query: { customer_segment_id: '9' },
  });
});

it('remounts the native dialog for an explicit different activity link, preserving other route filters', async () => {
  const wrapper = await render();
  const previous = editor(wrapper).vm;
  navigation.route.query.activityId = '446';
  await flushPromises();
  expect(editor(wrapper).props('activityId')).toBe(446);
  expect(editor(wrapper).vm).not.toBe(previous);
  expect(navigation.route.query.customer_segment_id).toBe('9');
  expect(activitiesAPI.create).not.toHaveBeenCalled();
});

it.each([
  ['array', ['445']],
  ['zero', '0'],
  ['scientific notation', '1e2'],
  ['unsafe integer', '9007199254740992'],
  ['whitespace', ' 445 '],
])(
  'does not open a fabricated or ambiguous %s record identifier',
  async (_kind, value) => {
    navigation.route.query.activityId = value;
    const wrapper = await render();
    expect(editor(wrapper).exists()).toBe(false);
    expect(activitiesAPI.create).not.toHaveBeenCalled();
    expect(activitiesAPI.complete).not.toHaveBeenCalled();
  }
);

it.each(['actor', 'grant', 'account'])(
  'closes and forgets the old activity after current %s replacement, without reopening it after initialization',
  async kind => {
    const wrapper = await render();
    expect(editor(wrapper).props('activityId')).toBe(445);
    if (kind === 'actor') authority.user = 8;
    else if (kind === 'grant') authority.grant = 5;
    else {
      authority.account = 2;
      navigation.route.params.accountId = '2';
    }
    await flushPromises();
    expect(editor(wrapper).exists()).toBe(false);
    expect(navigation.route.query).toEqual({ customer_segment_id: '9' });
    expect(activitiesAPI.create).not.toHaveBeenCalled();
    expect(activitiesAPI.complete).not.toHaveBeenCalled();
  }
);
