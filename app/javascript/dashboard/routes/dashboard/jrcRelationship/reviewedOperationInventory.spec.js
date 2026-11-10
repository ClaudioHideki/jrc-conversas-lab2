import { flushPromises, mount } from '@vue/test-utils';
import { defineComponent } from 'vue';
import Inventory from './ReviewedOperationInventory.vue';
import NativePanel from './ReviewedPortfolioBatchPanel.vue';
import { validOperationMetadata } from './reviewedOperationMetadata';
const api = vi.hoisted(() => ({
  ownReviewedBatches: vi.fn(),
  stopOwnReviewedBatch: vi.fn(),
  portfolioBatchReview: vi.fn(),
}));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: api }));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => `${key}${params ? JSON.stringify(params) : ''}`,
  }),
}));
const Dialog = defineComponent({
  setup(_, { expose }) {
    expose({ open: vi.fn() });
  },
  template: '<section><slot /></section>',
});
const row = {
  id: 51,
  revision: 1,
  state: 'previewed',
  operation: 'activity',
  created_at: '2026-11-06T12:00:00Z',
  updated_at: '2026-11-06T12:00:00Z',
  counts: { total: 2, pending: 2, applied: 0, failed: 0, canceled: 0 },
  can_cancel_pending: true,
};
const stopped = {
  ...row,
  revision: 2,
  state: 'canceled',
  can_cancel_pending: false,
  counts: { ...row.counts, pending: 0, canceled: 2 },
};
const response = (rows = [row], page = 1, total = rows.length) => ({
  data: { payload: rows, meta: { page, per_page: 25, total } },
});
const wrappers = [];
const render = (props = {}) => {
  const wrapper = mount(Inventory, {
    props: { accountId: '12', actorId: 7, ...props },
    global: { stubs: { Dialog } },
  });
  wrappers.push(wrapper);
  return wrapper;
};
const open = async wrapper => {
  wrapper.get('details').element.open = true;
  await wrapper.get('details').trigger('toggle');
  await flushPromises();
};
const choose = async wrapper => {
  await wrapper.get('[data-test="inventory-stop"]').trigger('click');
  await flushPromises();
  await wrapper
    .get('[data-test="inventory-reason"]')
    .setValue('Stop my remaining work');
};
beforeEach(() => {
  vi.clearAllMocks();
  sessionStorage.clear();
  api.ownReviewedBatches.mockResolvedValue(response());
  api.stopOwnReviewedBatch.mockResolvedValue({ data: stopped });
});
afterEach(() => wrappers.splice(0).forEach(wrapper => wrapper.unmount()));

it('loads lazily, filters and pages real own metadata with scoped abort options', async () => {
  const wrapper = render({ portfolioGroupId: 18 });
  expect(api.ownReviewedBatches).not.toHaveBeenCalled();
  api.ownReviewedBatches.mockResolvedValueOnce(response([row], 1, 26));
  await open(wrapper);
  expect(api.ownReviewedBatches).toHaveBeenCalledWith(
    '12',
    { page: 1, per_page: 25, status: 'pending', portfolio_group_id: 18 },
    expect.objectContaining({ signal: expect.any(AbortSignal) })
  );
  api.ownReviewedBatches.mockResolvedValueOnce(
    response([{ ...row, id: 52 }], 2, 26)
  );
  await wrapper.get('[data-test="inventory-next"]').trigger('click');
  await flushPromises();
  expect(wrapper.get('[data-test="inventory-row"]').text()).toContain('52');
  expect(wrapper.get('[data-test="inventory-row"]').text()).not.toContain('51');
  await wrapper.get('[data-test="inventory-status"]').setValue('all');
  await flushPromises();
  expect(api.ownReviewedBatches.mock.lastCall[1]).toEqual({
    page: 1,
    per_page: 25,
    status: 'all',
    portfolio_group_id: 18,
  });
});

it('requires an explicit reason and sends the selected exact revision without source or actor overrides', async () => {
  const wrapper = render();
  await open(wrapper);
  await wrapper.get('[data-test="inventory-stop"]').trigger('click');
  await flushPromises();
  expect(wrapper.get('[data-test="inventory-confirm"]').element.disabled).toBe(
    true
  );
  expect(api.stopOwnReviewedBatch).not.toHaveBeenCalled();
  await wrapper
    .get('[data-test="inventory-reason"]')
    .setValue(' Stop my remaining work ');
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(api.stopOwnReviewedBatch).toHaveBeenCalledWith(
    '12',
    51,
    { expected_revision: 1, reason: 'Stop my remaining work' },
    expect.any(Object)
  );
  expect(wrapper.find('[data-test="inventory-confirm"]').exists()).toBe(false);
  expect(wrapper.emitted('updated')).toHaveLength(1);
});

it.each([409, 500])(
  'requires a current metadata reread after %s and never retries a stop automatically',
  async code => {
    const wrapper = render({ portfolioGroupId: 18 });
    await open(wrapper);
    await choose(wrapper);
    api.stopOwnReviewedBatch.mockRejectedValueOnce({
      response: { status: code },
    });
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(
      wrapper.get('[data-test="inventory-confirm"]').element.disabled
    ).toBe(true);
    expect(wrapper.get('[data-test="inventory-reason"]').element.value).toBe(
      'Stop my remaining work'
    );
    api.ownReviewedBatches.mockResolvedValueOnce(
      response([{ ...row, revision: 3, state: 'running' }])
    );
    await wrapper.get('[data-test="inventory-reread"]').trigger('click');
    await flushPromises();
    expect(api.ownReviewedBatches.mock.lastCall[1]).toEqual({
      review_id: 51,
      status: 'all',
      page: 1,
      per_page: 25,
      portfolio_group_id: 18,
    });
    expect(api.stopOwnReviewedBatch).toHaveBeenCalledTimes(1);
    api.stopOwnReviewedBatch.mockResolvedValueOnce({
      data: { ...stopped, revision: 4 },
    });
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(api.stopOwnReviewedBatch.mock.lastCall[2].expected_revision).toBe(3);
  }
);

it('shows a raced completion as completion and preserves already applied outcomes', async () => {
  const wrapper = render();
  await open(wrapper);
  await choose(wrapper);
  api.stopOwnReviewedBatch.mockResolvedValueOnce({
    data: {
      ...stopped,
      state: 'completed',
      counts: { total: 2, pending: 0, applied: 2, failed: 0, canceled: 0 },
    },
  });
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(wrapper.text()).toContain(
    'RELATIONSHIP.REVIEWED_BATCH.STATES.completed'
  );
  expect(wrapper.get('[data-test="inventory-row"]').text()).not.toContain(
    'RELATIONSHIP.REVIEWED_BATCH.STATES.canceled'
  );
  expect(wrapper.find('form').exists()).toBe(false);
});

it('keeps an uncertain outcome blocked when closing and reopening the confirmation', async () => {
  const wrapper = render();
  await open(wrapper);
  await choose(wrapper);
  api.stopOwnReviewedBatch.mockRejectedValueOnce(
    new Error('Synthetic connection lost')
  );
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  wrapper.findComponent(Dialog).vm.$emit('close');
  await flushPromises();
  await choose(wrapper);
  expect(wrapper.get('[data-test="inventory-confirm"]').element.disabled).toBe(
    true
  );
  expect(api.stopOwnReviewedBatch).toHaveBeenCalledTimes(1);
  await wrapper.get('[data-test="inventory-reread"]').trigger('click');
  await flushPromises();
  expect(wrapper.get('[data-test="inventory-confirm"]').element.disabled).toBe(
    false
  );
});

it.each([
  { ...stopped, id: 999 },
  { ...stopped, counts: { ...stopped.counts, pending: 1 } },
])('rejects an HTTP 200 with an inconsistent stop receipt', async data => {
  const wrapper = render();
  await open(wrapper);
  await choose(wrapper);
  api.stopOwnReviewedBatch.mockResolvedValueOnce({ data });
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(wrapper.emitted('updated')).toBeUndefined();
  expect(wrapper.get('[data-test="inventory-confirm"]').element.disabled).toBe(
    true
  );
});

it('clears own controls when native authority is denied during a stop', async () => {
  const wrapper = render();
  await open(wrapper);
  await choose(wrapper);
  api.stopOwnReviewedBatch.mockRejectedValueOnce({ response: { status: 403 } });
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(wrapper.find('form').exists()).toBe(false);
  expect(wrapper.findAll('[data-test="inventory-row"]')).toHaveLength(0);
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
});

it('aborts identity changes and ignores late results rather than exposing an old account operation', async () => {
  let finish;
  api.ownReviewedBatches.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  const wrapper = render();
  await open(wrapper);
  const options = api.ownReviewedBatches.mock.lastCall[2];
  await wrapper.setProps({
    authorizationKey: 'new native membership',
    accountId: '13',
  });
  finish(response());
  await flushPromises();
  expect(options.signal.aborted).toBe(true);
  expect(wrapper.findAll('[data-test="inventory-row"]')).toHaveLength(0);
  expect(wrapper.find('form').exists()).toBe(false);
});

it('offers portfolio full details only inside the corresponding portfolio context', async () => {
  api.ownReviewedBatches.mockResolvedValue(
    response([{ ...row, operation: 'portfolio_membership' }])
  );
  const wrapper = render();
  await open(wrapper);
  expect(wrapper.find('[data-test="inventory-open"]').exists()).toBe(false);
  expect(wrapper.find('[data-test="inventory-stop"]').exists()).toBe(true);
  await wrapper.setProps({ portfolioGroupId: 18 });
  await open(wrapper);
  await wrapper.get('[data-test="inventory-open"]').trigger('click');
  expect(wrapper.emitted('open')).toEqual([[51]]);
});

it('rejects malformed list rows before enabling stop or navigation into details', async () => {
  expect(validOperationMetadata({ ...row, operation: 'invented' })).toBe(false);
  expect(
    validOperationMetadata({ ...row, counts: { ...row.counts, total: 600 } })
  ).toBe(false);
  api.ownReviewedBatches.mockResolvedValue(
    response([{ ...row, revision: '1' }])
  );
  const wrapper = render();
  await open(wrapper);
  expect(wrapper.findAll('[data-test="inventory-row"]')).toHaveLength(0);
  expect(wrapper.get('[role="alert"]').text()).toContain('UNCONFIRMED');
});

it('opens a saved operation through the existing native source-gated detail read without issuing a new preview', async () => {
  api.portfolioBatchReview.mockResolvedValue({
    data: {
      id: 51,
      revision: 1,
      state: 'previewed',
      digest: 'a'.repeat(64),
      inputs: { operation: 'activity', title: 'Saved native title' },
      items: [],
    },
  });
  const wrapper = mount(NativePanel, {
    props: { accountId: '12', actorId: 7, showInventory: true },
    global: { stubs: { Dialog, RouterLink: true } },
  });
  wrappers.push(wrapper);
  await open(wrapper.findComponent(Inventory));
  await wrapper.get('[data-test="inventory-open"]').trigger('click');
  await flushPromises();
  expect(api.portfolioBatchReview).toHaveBeenCalledWith(
    '12',
    51,
    expect.any(Object)
  );
  expect(wrapper.text()).toContain('Saved native title');
  expect(sessionStorage.getItem('relationship-reviewed-batch:12:7')).toBe('51');
});

it('rereads the selected saved operation after a failed detail response rather than falling back to an older cached operation', async () => {
  sessionStorage.setItem('relationship-reviewed-batch:12:7', '41');
  api.portfolioBatchReview.mockRejectedValue({ response: { status: 500 } });
  const wrapper = mount(NativePanel, {
    props: { accountId: '12', actorId: 7, showInventory: true },
    global: { stubs: { Dialog, RouterLink: true } },
  });
  wrappers.push(wrapper);
  await flushPromises();
  await open(wrapper.findComponent(Inventory));
  await wrapper.get('[data-test="inventory-open"]').trigger('click');
  await flushPromises();
  await wrapper.get('[data-test="review-refresh"]').trigger('click');
  await flushPromises();
  expect(api.portfolioBatchReview.mock.calls.map(call => call[1])).toEqual([
    41, 51, 51,
  ]);
});
