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
let store;
beforeEach(() => {
  vi.resetAllMocks();
  navigation.route = reactive({
    params: { accountId: '1' },
    query: { date: '2026-11-07T09:00:00' },
  });
  store = createStore({
    getters: {
      getCurrentAccountId: () => 1,
      getCurrentUserID: () => 7,
      getCurrentRole: () => 'agent',
      getCurrentUser: () => ({ accounts: [] }),
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
  activitiesAPI.list.mockResolvedValue({
    data: [
      {
        id: 1,
        title: 'Authorized selected-day appointment',
        activity_type: 'meeting',
        due_at: '2026-11-07T12:00:00Z',
        status: 'scheduled',
      },
      {
        id: 2,
        title: 'Authorized next-week appointment',
        activity_type: 'call',
        due_at: '2026-11-09T12:00:00Z',
        status: 'scheduled',
      },
      {
        id: 3,
        title: 'Authorized first-month appointment',
        activity_type: 'email',
        due_at: '2026-11-01T12:00:00Z',
        status: 'completed',
        completed_at: '2026-11-01T13:00:00Z',
      },
      {
        id: 4,
        title: 'Authorized following-month appointment',
        activity_type: 'meeting',
        due_at: '2026-12-01T12:00:00Z',
        status: 'scheduled',
      },
    ],
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
const mode = async name =>
  wrapper.get(`[data-testid="calendar-view-${name}"]`).trigger('click');
const grid = () => wrapper.get('[data-testid="calendar-period"]');

it.each(['month', 'day', 'list', 'week'])(
  'opens the working %s view over the same native authorized list without another transport call',
  async name => {
    await render();
    expect(
      wrapper.get(`[data-testid="calendar-view-${name}"]`).element.disabled
    ).toBe(false);
    await mode(name);
    expect(
      wrapper
        .get(`[data-testid="calendar-view-${name}"]`)
        .attributes('aria-current')
    ).toBe('true');
    expect(activitiesAPI.list).toHaveBeenCalledTimes(1);
  }
);

it('keeps the native weekly period distinct from later weeks and other months', async () => {
  await render();
  expect(grid().findAll('[data-calendar-day]')).toHaveLength(7);
  expect(grid().text()).toContain('Authorized selected-day appointment');
  expect(grid().text()).not.toContain('Authorized next-week appointment');
  expect(grid().text()).not.toContain('Authorized first-month appointment');
  expect(grid().text()).not.toContain('Authorized following-month appointment');
});

it('renders a six-week month with local date keys and opens the selected native day', async () => {
  await render();
  await mode('month');
  const days = grid().findAll('[data-calendar-day]');
  expect(days).toHaveLength(42);
  expect(days[0].attributes('data-calendar-day')).toBe('2026-10-26');
  expect(days[41].attributes('data-calendar-day')).toBe('2026-12-06');
  await grid()
    .get('[data-calendar-day="2026-11-09"] [data-testid="calendar-open-day"]')
    .trigger('click');
  expect(grid().findAll('[data-calendar-day]')).toHaveLength(1);
  expect(grid().text()).toContain('Authorized next-week appointment');
  expect(grid().text()).not.toContain('Authorized selected-day appointment');
});

it('limits the day view to the selected local date', async () => {
  await render();
  await mode('day');
  expect(grid().findAll('[data-calendar-day]')).toHaveLength(1);
  expect(
    grid().get('[data-calendar-day]').attributes('data-calendar-day')
  ).toBe('2026-11-07');
  expect(grid().text()).toContain('Authorized selected-day appointment');
  expect(grid().text()).not.toContain('Authorized next-week appointment');
});

it('lists real appointments for the selected month, including completed records, without inventing rows', async () => {
  await render();
  await mode('list');
  expect(grid().findAll('article')).toHaveLength(3);
  expect(grid().text()).toContain('Authorized first-month appointment');
  expect(grid().text()).toContain('Authorized next-week appointment');
  expect(grid().text()).not.toContain('Authorized following-month appointment');
});

it('moves by the active week or day rather than always jumping one month', async () => {
  await render();
  await wrapper.get('[data-testid="calendar-next-period"]').trigger('click');
  expect(grid().text()).toContain('Authorized next-week appointment');
  expect(grid().text()).not.toContain('Authorized selected-day appointment');
  await mode('day');
  const original = grid()
    .get('[data-calendar-day]')
    .attributes('data-calendar-day');
  await wrapper
    .get('[data-testid="calendar-previous-period"]')
    .trigger('click');
  expect(
    grid().get('[data-calendar-day]').attributes('data-calendar-day')
  ).not.toBe(original);
  expect(
    grid().get('[data-calendar-day]').attributes('data-calendar-day')
  ).toBe('2026-11-13');
  expect(activitiesAPI.list).toHaveBeenCalledTimes(1);
});

it('moves the list by month and displays a real empty state after the last known month', async () => {
  await render();
  await mode('list');
  await wrapper.get('[data-testid="calendar-next-period"]').trigger('click');
  expect(grid().findAll('article')).toHaveLength(1);
  expect(grid().text()).toContain('Authorized following-month appointment');
  await wrapper.get('[data-testid="calendar-next-period"]').trigger('click');
  expect(wrapper.find('[data-testid="calendar-empty-period"]').exists()).toBe(
    true
  );
  expect(wrapper.find('[data-testid="calendar-period"]').exists()).toBe(false);
});

it('follows a native date link reactively while retaining the chosen view', async () => {
  await render();
  await mode('day');
  navigation.route.query.date = '2026-12-01T09:00:00';
  await flushPromises();
  expect(grid().text()).toContain('Authorized following-month appointment');
  expect(grid().text()).not.toContain('Authorized selected-day appointment');
  expect(
    wrapper.get('[data-testid="calendar-view-day"]').attributes('aria-current')
  ).toBe('true');
  expect(activitiesAPI.list).toHaveBeenCalledTimes(1);
});

it('pages appointments rather than days without losing or repeating authorized rows', async () => {
  activitiesAPI.list.mockResolvedValueOnce({
    data: Array.from({ length: 61 }, (_, index) => ({
      id: index + 10,
      title: `Authorized appointment ${index + 1}`,
      due_at: index < 30 ? '2026-11-07T12:00:00Z' : '2026-11-09T12:00:00Z',
      status: 'scheduled',
    })),
  });
  await render();
  await mode('list');
  const titles = [];
  await [25, 25, 11].reduce(async (previous, count) => {
    await previous;
    const cards = grid().findAll('article');
    expect(cards).toHaveLength(count);
    titles.push(...cards.map(card => card.get('p').text()));
    if (count === 25) {
      await wrapper.get('[data-testid="calendar-list-next"]').trigger('click');
    }
  }, Promise.resolve());
  expect(new Set(titles).size).toBe(61);
  expect(titles[0]).toBe('Authorized appointment 1');
  expect(titles[60]).toBe('Authorized appointment 61');
  expect(
    wrapper.get('[data-testid="calendar-list-next"]').element.disabled
  ).toBe(true);
  await wrapper.get('[data-testid="calendar-list-previous"]').trigger('click');
  expect(grid().findAll('article')).toHaveLength(25);
  expect(grid().findAll('article')[0].text()).toContain(
    'Authorized appointment 26'
  );
  expect(activitiesAPI.list).toHaveBeenCalledTimes(1);
});

it('resets the page when filtering, clearing filters or changing the period', async () => {
  activitiesAPI.list.mockResolvedValueOnce({
    data: Array.from({ length: 30 }, (_, index) => ({
      id: index + 10,
      title: index === 29 ? 'Unique appointment' : `Meeting ${index}`,
      due_at: '2026-11-07T12:00:00Z',
      status: 'scheduled',
    })),
  });
  await render();
  await mode('list');
  await wrapper.get('[data-testid="calendar-list-next"]').trigger('click');
  await wrapper
    .get('[data-testid="calendar-filter-search"]')
    .setValue('Unique');
  expect(grid().findAll('article')).toHaveLength(1);
  expect(grid().text()).toContain('Unique appointment');
  expect(
    wrapper.get('[data-testid="calendar-list-previous"]').element.disabled
  ).toBe(true);
  await wrapper.get('[data-testid="calendar-clear-filters"]').trigger('click');
  expect(grid().findAll('article')).toHaveLength(25);
  await wrapper.get('[data-testid="calendar-list-next"]').trigger('click');
  await wrapper.get('[data-testid="calendar-next-period"]').trigger('click');
  expect(wrapper.find('[data-testid="calendar-list-next"]').exists()).toBe(
    false
  );
  await wrapper
    .get('[data-testid="calendar-previous-period"]')
    .trigger('click');
  expect(grid().findAll('article')).toHaveLength(25);
  expect(activitiesAPI.list).toHaveBeenCalledTimes(1);
});

it('clamps a later page after a native refresh shrinks the result, preserving full day and month views', async () => {
  activitiesAPI.list.mockResolvedValueOnce({
    data: Array.from({ length: 30 }, (_, index) => ({
      id: index + 10,
      title: `Current appointment ${index}`,
      due_at: '2026-11-07T12:00:00Z',
      status: 'scheduled',
    })),
  });
  await render();
  await mode('day');
  expect(grid().findAll('article')).toHaveLength(30);
  await mode('month');
  expect(grid().findAll('article')).toHaveLength(30);
  await mode('list');
  await wrapper.get('[data-testid="calendar-list-next"]').trigger('click');
  store.commit('jrcCrm/activities/SET_ACTIVITIES', [
    {
      id: 100,
      title: 'Remaining authorized appointment',
      due_at: '2026-11-07T12:00:00Z',
      status: 'scheduled',
    },
  ]);
  await flushPromises();
  expect(grid().findAll('article')).toHaveLength(1);
  expect(grid().text()).toContain('Remaining authorized appointment');
  expect(grid().text()).not.toContain('Current appointment');
  expect(
    wrapper.get('[data-testid="calendar-list-previous"]').element.disabled
  ).toBe(true);
});
