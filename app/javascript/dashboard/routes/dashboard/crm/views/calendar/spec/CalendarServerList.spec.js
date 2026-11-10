import { mount, flushPromises } from '@vue/test-utils';
import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import CalendarServerList from '../CalendarServerList.vue';
import { activitiesAPI } from 'dashboard/api/crm';

vi.mock('dashboard/api/crm', () => ({
  activitiesAPI: { calendarPageInAccount: vi.fn(), completeInAccount: vi.fn() },
}));
let wrapper;
const pageResponse = (page = 1, total = 26) => ({
  data: {
    data: Array.from(
      { length: Math.min(25, Math.max(0, total - (page - 1) * 25)) },
      (_, i) => ({
        id: (page - 1) * 25 + i + 1,
        title: `Synthetic appointment ${(page - 1) * 25 + i + 1}`,
        due_at_local: '2026-11-07T23:00:00',
        due_at_display: '07/11/2026 23:00',
        status: 'scheduled',
      })
    ),
    owners: [{ id: 7, name: 'Synthetic owner' }],
    meta: {
      total,
      page,
      per_page: 25,
      pages: Math.max(1, Math.ceil(total / 25)),
    },
  },
});
const render = async () => {
  wrapper = mount(CalendarServerList, {
    props: {
      accountId: 1,
      identity: '1:7:agent',
      startsOn: '2026-11-01',
      endsBefore: '2026-12-01',
      filters: {},
    },
    global: {
      stubs: {
        Button: {
          props: ['label', 'disabled'],
          template: '<button :disabled="disabled">{{ label }}</button>',
        },
      },
    },
  });
  await flushPromises();
};
beforeEach(() => {
  vi.resetAllMocks();
  activitiesAPI.calendarPageInAccount.mockResolvedValue(pageResponse());
  activitiesAPI.completeInAccount.mockResolvedValue({ data: {} });
});
afterEach(() => wrapper?.unmount());

describe('native server calendar list', () => {
  it('fetches only one bounded page in the explicit account', async () => {
    await render();
    expect(wrapper.findAll('article')).toHaveLength(25);
    expect(activitiesAPI.calendarPageInAccount).toHaveBeenCalledWith(
      1,
      expect.objectContaining({ page: 1, per_page: 25 }),
      expect.any(Object)
    );
  });
  it('requests the next page instead of slicing the loaded records', async () => {
    await render();
    activitiesAPI.calendarPageInAccount.mockResolvedValueOnce(pageResponse(2));
    await wrapper.get('[data-testid="calendar-list-next"]').trigger('click');
    await flushPromises();
    expect(wrapper.findAll('article')).toHaveLength(1);
    expect(wrapper.text()).toContain('Synthetic appointment 26');
  });
  it('resets to the first page when filters change', async () => {
    await render();
    await wrapper.setProps({
      filters: { search: 'renewal', type: 'call', status: 'open' },
    });
    await flushPromises();
    expect(activitiesAPI.calendarPageInAccount).toHaveBeenLastCalledWith(
      1,
      expect.objectContaining({
        page: 1,
        search: 'renewal',
        activity_type: 'call',
        status: 'open',
      }),
      expect.any(Object)
    );
  });
  it('removes visible records when a new authorized query is denied', async () => {
    await render();
    activitiesAPI.calendarPageInAccount.mockRejectedValueOnce({
      response: { status: 403 },
    });
    await wrapper.setProps({ revision: 1 });
    await flushPromises();
    expect(wrapper.findAll('article')).toHaveLength(0);
    expect(wrapper.text()).not.toContain('Synthetic appointment');
    expect(wrapper.emitted('owners').at(-1)).toEqual([[]]);
  });
  it('does not display a late response belonging to the previous account', async () => {
    let resolve;
    activitiesAPI.calendarPageInAccount.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    await render();
    await wrapper.setProps({ accountId: 2, identity: '2:7:agent' });
    await flushPromises();
    resolve({
      data: {
        ...pageResponse().data,
        data: [{ id: 999, title: 'OLD PRIVATE RESPONSE' }],
      },
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain('OLD PRIVATE RESPONSE');
  });
  it('groups a late appointment by the account date supplied by the server', async () => {
    await render();
    expect(
      wrapper.get('[data-calendar-day]').attributes('data-calendar-day')
    ).toBe('2026-11-07');
  });
  it('preserves the native edit action and does not mutate a record on read', async () => {
    await render();
    await wrapper.findAll('article')[0].findAll('button')[0].trigger('click');
    expect(wrapper.emitted('edit')).toEqual([[1]]);
    expect(activitiesAPI.completeInAccount).not.toHaveBeenCalled();
  });
  it('forwards the customer segment without broadening the authorized account', async () => {
    await render();
    await wrapper.setProps({ customerSegmentId: 5 });
    await flushPromises();
    expect(activitiesAPI.calendarPageInAccount).toHaveBeenLastCalledWith(
      1,
      expect.objectContaining({ customer_segment_id: 5 }),
      expect.any(Object)
    );
  });
});
