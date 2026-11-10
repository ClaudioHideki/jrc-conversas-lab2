import { mount, flushPromises, RouterLinkStub } from '@vue/test-utils';
import { reactive } from 'vue';
import { beforeEach, expect, it, vi } from 'vitest';
import Component from './AnalystCadencesDialog.vue';

const mocks = vi.hoisted(() => ({
  route: null,
  getters: null,
  list: vi.fn(),
  stop: vi.fn(),
}));
vi.mock('vue-router', async original => ({
  ...(await original()),
  useRoute: () => mocks.route,
}));
vi.mock('vuex', () => ({ useStore: () => ({ getters: mocks.getters }) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcRelationship', () => ({
  default: { analystCadences: mocks.list, stopAnalystCadence: mocks.stop },
}));
const Dialog = {
  setup(_, { expose }) {
    expose({ open: vi.fn() });
  },
  template: '<section><slot /></section>',
};
const response = (revision = 3, page = 1) => ({
  data: {
    analyst: { id: 7, name: 'Current native analyst' },
    can_stop: true,
    payload: [
      {
        id: 14,
        revision,
        assignment_id: 5,
        customer_name: 'Authorized customer',
        pending_steps: 2,
        responsibility: 'execution_actor',
        next_due_at: '2026-11-10T12:00:00Z',
        customer_360: { name: 'contacts_edit', params: { contactId: 9 } },
      },
    ],
    meta: { page, per_page: 10, total: 11 },
  },
});
const render = () =>
  mount(Component, {
    props: { analystId: 7 },
    global: { stubs: { Dialog, RouterLink: RouterLinkStub } },
  });
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ params: { accountId: '1' } });
  mocks.getters = reactive({
    getCurrentUserID: 3,
    getCurrentRole: 'administrator',
    getCurrentUser: { accounts: [] },
  });
  mocks.list.mockResolvedValue(response());
  mocks.stop.mockResolvedValue({ data: { state: 'stopped', revision: 4 } });
});

it('paginates current native rows and opens the authorized customer with the current account', async () => {
  const wrapper = render();
  await flushPromises();
  expect(wrapper.text()).toContain('Authorized customer');
  expect(wrapper.text()).toContain('DEPENDENCIES.execution_actor');
  expect(wrapper.findComponent(RouterLinkStub).props('to')).toEqual({
    name: 'contacts_edit',
    params: { contactId: 9, accountId: '1' },
  });
  mocks.list.mockResolvedValueOnce(response(3, 2));
  await wrapper.get('[data-testid="cadence-team-next"]').trigger('click');
  await flushPromises();
  expect(mocks.list).toHaveBeenLastCalledWith(
    '1',
    7,
    { page: 2 },
    { signal: expect.any(AbortSignal) }
  );
  expect(
    wrapper.get('[data-testid="cadence-team-next"]').element.disabled
  ).toBe(true);
  expect(mocks.stop).not.toHaveBeenCalled();
  wrapper.unmount();
});

it('requires an explicit reason and uses the captured revision before confirming an actual stop', async () => {
  const wrapper = render();
  await flushPromises();
  await wrapper.get('[data-testid="cadence-team-review"]').trigger('click');
  await wrapper.get('form').trigger('submit');
  expect(mocks.stop).not.toHaveBeenCalled();
  await wrapper
    .get('[data-testid="cadence-team-reason"]')
    .setValue('Reviewed schedule; remaining steps are no longer needed.');
  const empty = response();
  empty.data.payload = [];
  empty.data.meta.total = 0;
  mocks.list.mockResolvedValueOnce(empty);
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(mocks.stop).toHaveBeenCalledWith('1', 7, 14, {
    expected_revision: 3,
    reason: 'Reviewed schedule; remaining steps are no longer needed.',
  });
  expect(wrapper.emitted('changed')).toHaveLength(1);
  expect(wrapper.text()).toContain('CADENCE_TEAM.STOPPED');
  expect(wrapper.find('[data-testid="cadence-team-row"]').exists()).toBe(false);
  wrapper.unmount();
});

it('retains a reason draft after conflict but requires a new row review before using its refreshed revision', async () => {
  const wrapper = render();
  await flushPromises();
  await wrapper.get('[data-testid="cadence-team-review"]').trigger('click');
  await wrapper
    .get('[data-testid="cadence-team-reason"]')
    .setValue('Supervisor reviewed this schedule.');
  mocks.stop.mockRejectedValueOnce({
    response: { status: 409, data: { errors: ['Record changed'] } },
  });
  mocks.list.mockResolvedValueOnce(response(4));
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(mocks.stop).toHaveBeenCalledTimes(1);
  expect(wrapper.find('form').exists()).toBe(false);
  expect(wrapper.text()).toContain('Record changed');
  await wrapper.get('[data-testid="cadence-team-review"]').trigger('click');
  expect(wrapper.get('[data-testid="cadence-team-reason"]').element.value).toBe(
    'Supervisor reviewed this schedule.'
  );
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(mocks.stop).toHaveBeenLastCalledWith('1', 7, 14, {
    expected_revision: 4,
    reason: 'Supervisor reviewed this schedule.',
  });
  wrapper.unmount();
});

it('does not offer mutation when the current server projection grants read only', async () => {
  const data = response();
  data.data.can_stop = false;
  mocks.list.mockResolvedValueOnce(data);
  const wrapper = render();
  await flushPromises();
  expect(wrapper.find('[data-testid="cadence-team-review"]').exists()).toBe(
    false
  );
  expect(mocks.stop).not.toHaveBeenCalled();
  wrapper.unmount();
});

it('clears customer labels and draft content after a server-side permission revocation', async () => {
  const wrapper = render();
  await flushPromises();
  await wrapper.get('[data-testid="cadence-team-review"]').trigger('click');
  await wrapper
    .get('[data-testid="cadence-team-reason"]')
    .setValue('Private review draft');
  mocks.stop.mockRejectedValueOnce({
    response: { status: 403, data: { errors: ['Access revoked'] } },
  });
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(wrapper.text()).not.toContain('Authorized customer');
  expect(wrapper.find('form').exists()).toBe(false);
  expect(wrapper.emitted('changed')).toBeUndefined();
  wrapper.unmount();
});

it('aborts stale reads and closes when identity or role changes', async () => {
  const wrapper = render();
  await flushPromises();
  const signal = mocks.list.mock.calls[0][3].signal;
  mocks.getters.getCurrentRole = 'agent';
  await flushPromises();
  expect(signal.aborted).toBe(true);
  expect(wrapper.text()).not.toContain('Authorized customer');
  expect(wrapper.emitted('close')).toHaveLength(1);
  wrapper.unmount();
});

it('returns to an existing page after stopping the last row on the final page', async () => {
  const wrapper = render();
  await flushPromises();
  mocks.list.mockResolvedValueOnce(response(3, 2));
  await wrapper.get('[data-testid="cadence-team-next"]').trigger('click');
  await flushPromises();
  await wrapper.get('[data-testid="cadence-team-review"]').trigger('click');
  await wrapper
    .get('[data-testid="cadence-team-reason"]')
    .setValue('End reviewed pending schedule.');
  const emptyLastPage = response(3, 2);
  emptyLastPage.data.payload = [];
  emptyLastPage.data.meta.total = 10;
  const remaining = response(3, 1);
  remaining.data.payload[0].id = 15;
  remaining.data.payload[0].customer_name = 'Remaining authorized customer';
  remaining.data.meta.total = 10;
  mocks.list
    .mockResolvedValueOnce(emptyLastPage)
    .mockResolvedValueOnce(remaining);
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(mocks.list).toHaveBeenLastCalledWith(
    '1',
    7,
    { page: 1 },
    expect.any(Object)
  );
  expect(wrapper.text()).toContain('Remaining authorized customer');
  expect(wrapper.find('[data-testid="cadence-team-next"]').exists()).toBe(
    false
  );
  wrapper.unmount();
});

it('does not publish a stale change event when identity changes during the post-stop refresh', async () => {
  const wrapper = render();
  await flushPromises();
  await wrapper.get('[data-testid="cadence-team-review"]').trigger('click');
  await wrapper
    .get('[data-testid="cadence-team-reason"]')
    .setValue('Reviewed pending work.');
  let resolveRefresh;
  mocks.list.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        resolveRefresh = resolve;
      })
  );
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  mocks.getters.getCurrentRole = 'agent';
  await flushPromises();
  resolveRefresh(response());
  await flushPromises();
  expect(wrapper.emitted('changed')).toBeUndefined();
  expect(wrapper.text()).not.toContain('Authorized customer');
  wrapper.unmount();
});
