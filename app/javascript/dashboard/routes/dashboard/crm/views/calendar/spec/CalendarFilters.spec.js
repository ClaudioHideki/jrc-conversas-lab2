import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { createStore } from 'vuex';
import { beforeEach, afterEach, it, expect, vi } from 'vitest';
import CalendarView from '../CalendarView.vue';
import activities from 'dashboard/store/crm/modules/activities';
import { activitiesAPI } from 'dashboard/api/crm';

const navigation = vi.hoisted(() => ({ route: null }));
vi.mock('vue-router', () => ({ useRoute: () => navigation.route }));
vi.mock('dashboard/api/crm', () => ({
  activitiesAPI: { list: vi.fn(), complete: vi.fn() },
}));
let wrapper;
let authority;
let store;
const sources = () => [
  {
    id: 1,
    title: 'Native renewal call',
    activity_type: 'call',
    user: { id: 7, name: 'Native owner seven' },
    deal: { title: 'Authorized origin' },
    due_at: '2026-11-07T12:00:00Z',
    status: 'scheduled',
    overdue: true,
  },
  {
    id: 2,
    title: 'Native team meeting',
    activity_type: 'meeting',
    user: { id: 8, name: 'Native owner eight' },
    due_at: '2026-11-07T14:00:00Z',
    status: 'scheduled',
  },
  {
    id: 3,
    title: 'Native completed call',
    activity_type: 'call',
    user: { id: 7, name: 'Native owner seven' },
    due_at: '2026-11-07T15:00:00Z',
    status: 'completed',
    completed_at: '2026-11-07T16:00:00Z',
  },
  {
    id: 4,
    title: 'Native canceled call',
    activity_type: 'call',
    user: { id: 9, name: 'Native owner nine' },
    due_at: '2026-11-07T17:00:00Z',
    status: 'cancelled',
  },
];
beforeEach(() => {
  vi.resetAllMocks();
  authority = reactive({
    account: 1,
    actor: 7,
    role: 'agent',
    presence: 'online',
  });
  navigation.route = reactive({
    params: { accountId: '1' },
    query: { date: '2026-11-07T09:00:00' },
  });
  store = createStore({
    getters: {
      getCurrentAccountId: () => authority.account,
      getCurrentUserID: () => authority.actor,
      getCurrentRole: () => authority.role,
      getCurrentUser: () => ({
        id: authority.actor,
        accounts: [
          {
            id: authority.account,
            role: authority.role,
            availability: authority.presence,
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
        },
      },
    },
  });
  activitiesAPI.list.mockResolvedValue({ data: sources() });
  activitiesAPI.complete.mockResolvedValue({
    data: {
      ...sources()[0],
      status: 'completed',
      completed_at: '2026-11-07T18:00:00Z',
    },
  });
});
afterEach(() => wrapper?.unmount());
const render = async () => {
  wrapper = mount(CalendarView, {
    global: {
      plugins: [store],
      stubs: {
        RouterLink: true,
        CrmPageHeader: true,
        ActivityEditDialog: true,
      },
    },
  });
  await flushPromises();
};
const filter = (name, value) =>
  wrapper.get(`[data-testid="calendar-filter-${name}"]`).setValue(value);
const cards = () =>
  wrapper.get('[data-testid="calendar-period"]').findAll('article');

it('combines native search, type, owner and status without fetching or granting additional records', async () => {
  await render();
  await filter('type', 'call');
  await filter('owner', '7');
  await filter('status', 'overdue');
  await filter('search', 'AUTHORIZED ORIGIN');
  expect(cards()).toHaveLength(1);
  expect(cards()[0].text()).toContain('Native renewal call');
  expect(activitiesAPI.list).toHaveBeenCalledTimes(1);
  expect(activitiesAPI.complete).not.toHaveBeenCalled();
  expect(wrapper.get('[data-testid="calendar-filter-owner"]').text()).toContain(
    'Native owner eight'
  );
});

it('uses native completion and cancellation semantics for open and completed filters', async () => {
  await render();
  await filter('status', 'open');
  expect(cards()).toHaveLength(2);
  await filter('status', 'completed');
  expect(cards()).toHaveLength(1);
  expect(cards()[0].text()).toContain('Native completed call');
  expect(cards()[0].find('button').exists()).toBe(false);
});

it('clears every filter while keeping the selected native date and view', async () => {
  await render();
  await wrapper.get('[data-testid="calendar-view-list"]').trigger('click');
  await filter('search', 'renewal');
  await filter('type', 'call');
  await filter('owner', '7');
  await filter('status', 'open');
  await wrapper.get('[data-testid="calendar-clear-filters"]').trigger('click');
  expect(
    wrapper
      .findAll('[data-testid^="calendar-filter-"]')
      .map(control => control.element.value)
  ).toEqual(['', '', '', '']);
  expect(cards()).toHaveLength(4);
  expect(
    wrapper.get('[data-testid="calendar-view-list"]').attributes('aria-current')
  ).toBe('true');
  expect(navigation.route.query.date).toBe('2026-11-07T09:00:00');
  expect(activitiesAPI.list).toHaveBeenCalledTimes(1);
});

it('removes old owner choices and filters when the native account is replaced', async () => {
  await render();
  await filter('owner', '7');
  await filter('search', 'renewal');
  activitiesAPI.list.mockResolvedValueOnce({
    data: [
      {
        ...sources()[0],
        id: 22,
        title: 'Current tenant appointment',
        user: { id: 99, name: 'Current tenant owner' },
      },
    ],
  });
  authority.account = 2;
  navigation.route.params.accountId = '2';
  await flushPromises();
  expect(
    wrapper.get('[data-testid="calendar-filter-owner"]').element.value
  ).toBe('');
  expect(
    wrapper.get('[data-testid="calendar-filter-search"]').element.value
  ).toBe('');
  expect(wrapper.text()).toContain('Current tenant appointment');
  expect(wrapper.text()).not.toContain('Native owner seven');
  expect(wrapper.get('[data-testid="calendar-filter-owner"]').text()).toContain(
    'Current tenant owner'
  );
});

it('retains current filters through a presence-only native update', async () => {
  await render();
  await filter('owner', '7');
  await filter('status', 'open');
  authority.presence = 'offline';
  await flushPromises();
  expect(
    wrapper.get('[data-testid="calendar-filter-owner"]').element.value
  ).toBe('7');
  expect(
    wrapper.get('[data-testid="calendar-filter-status"]').element.value
  ).toBe('open');
  expect(cards()).toHaveLength(1);
  expect(activitiesAPI.list).toHaveBeenCalledTimes(1);
});

it('keeps the active filter across the real period view switches', async () => {
  await render();
  await filter('type', 'meeting');
  await wrapper.get('[data-testid="calendar-view-month"]').trigger('click');
  expect(cards()).toHaveLength(1);
  await wrapper.get('[data-testid="calendar-view-day"]').trigger('click');
  expect(cards()).toHaveLength(1);
  expect(cards()[0].text()).toContain('Native team meeting');
  expect(
    wrapper.get('[data-testid="calendar-filter-type"]').element.value
  ).toBe('meeting');
});

it('refreshes native persistence after completion and re-applies the open filter to the returned source', async () => {
  await render();
  await filter('owner', '7');
  await filter('status', 'open');
  const persisted = sources();
  persisted[0] = {
    ...persisted[0],
    status: 'completed',
    completed_at: '2026-11-07T18:00:00Z',
  };
  activitiesAPI.list.mockResolvedValueOnce({ data: persisted });
  await cards()[0].get('button').trigger('click');
  await flushPromises();
  expect(activitiesAPI.complete).toHaveBeenCalledWith(1);
  expect(activitiesAPI.list).toHaveBeenCalledTimes(2);
  expect(cards()).toHaveLength(0);
  expect(wrapper.text()).not.toContain('Native renewal call');
});

it.each([
  ['account', 2],
  ['role', 'revoked'],
])(
  'clears paged content after a denied native %s replacement',
  async (field, value) => {
    activitiesAPI.list.mockResolvedValueOnce({
      data: Array.from({ length: 30 }, (_, index) => ({
        ...sources()[0],
        id: index + 10,
        title: `Previous private appointment ${index}`,
      })),
    });
    await render();
    await wrapper.get('[data-testid="calendar-view-list"]').trigger('click');
    await wrapper.get('[data-testid="calendar-list-next"]').trigger('click');
    expect(cards()).toHaveLength(5);
    activitiesAPI.list.mockRejectedValueOnce({
      response: { status: 403, data: { error: 'Access denied' } },
    });
    authority[field] = value;
    if (field === 'account') navigation.route.params.accountId = String(value);
    await flushPromises();
    expect(wrapper.text()).toContain('Access denied');
    expect(wrapper.text()).not.toContain('Previous private appointment');
    expect(wrapper.find('[data-testid="calendar-list-next"]').exists()).toBe(
      false
    );
    expect(activitiesAPI.list).toHaveBeenCalledTimes(2);
    expect(activitiesAPI.complete).not.toHaveBeenCalled();
  }
);
