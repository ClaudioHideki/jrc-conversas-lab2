import { mount, flushPromises } from '@vue/test-utils';
import { afterEach, expect, it, vi } from 'vitest';
import ReviewedCadencePanel from './ReviewedCadencePanel.vue';
const api = vi.hoisted(() => ({
  cadence: vi.fn(),
  advanceCadence: vi.fn(),
  cancelCadence: vi.fn(),
}));
vi.mock('dashboard/api/jrcRelationship', () => ({ default: api }));
let wrapper;
afterEach(() => {
  wrapper?.unmount();
  vi.clearAllMocks();
});
it('displays persisted budget deferral as pending and does not advance automatically or invent a receipt', async () => {
  const record = {
    id: 18,
    revision: 2,
    state: 'active',
    book_name: 'Native budget-governed book',
    book_version: 1,
    retry_at: '2026-11-06T03:00:00.000000Z',
    steps: [
      {
        ordinal: 1,
        title: 'Pending native work',
        state: 'pending',
        receipt: null,
      },
    ],
  };
  api.cadence.mockResolvedValue({ data: record });
  wrapper = mount(ReviewedCadencePanel, {
    props: { accountId: '7', cadenceId: 18 },
  });
  await flushPromises();
  expect(
    wrapper.get('[data-testid="cadence-budget-deferred"]').attributes('role')
  ).toBe('status');
  expect(wrapper.text()).toContain('2026-11-06T03:00:00.000000Z');
  expect(wrapper.text()).toContain('Pending native work');
  expect(api.advanceCadence).not.toHaveBeenCalled();
  expect(api.cancelCadence).not.toHaveBeenCalled();
});
it('only reads the approved enrollment until explicit advance or cancellation', async () => {
  const record = {
    id: 18,
    revision: 1,
    state: 'active',
    book_name: 'Frozen native book',
    book_version: 3,
    steps: [
      {
        ordinal: 0,
        title: 'One native task',
        due_at: '2026-10-20T12:00:00Z',
        state: 'pending',
      },
    ],
  };
  api.cadence.mockResolvedValue({ data: record });
  api.cancelCadence.mockResolvedValue({
    data: {
      ...record,
      revision: 2,
      state: 'stopped',
      stop_reason: 'CANCELED_BY_OPERATOR',
    },
  });
  wrapper = mount(ReviewedCadencePanel, {
    props: { accountId: '7', cadenceId: 18 },
  });
  await flushPromises();
  expect(wrapper.text()).toContain('Frozen native book');
  expect(api.advanceCadence).not.toHaveBeenCalled();
  await wrapper.get('[data-test="cadence-cancel"]').trigger('click');
  await flushPromises();
  expect(api.cancelCadence).toHaveBeenCalledWith('7', 18, expect.any(Object));
  expect(wrapper.find('[data-test="cadence-cancel"]').exists()).toBe(false);
});
it('clears the frozen book and deferral details after native access is denied', async () => {
  api.cadence.mockResolvedValueOnce({
    data: {
      id: 18,
      revision: 2,
      state: 'active',
      book_name: 'Synthetic restricted book',
      retry_at: '2026-11-06T03:00:00Z',
      steps: [],
    },
  });
  wrapper = mount(ReviewedCadencePanel, {
    props: { accountId: '7', cadenceId: 18 },
  });
  await flushPromises();
  expect(wrapper.text()).toContain('Synthetic restricted book');
  api.cadence.mockRejectedValueOnce({ response: { status: 403 } });
  await wrapper.get('[data-test="cadence-refresh"]').trigger('click');
  await flushPromises();
  expect(wrapper.text()).not.toContain('Synthetic restricted book');
  expect(wrapper.find('[data-testid="cadence-budget-deferred"]').exists()).toBe(
    false
  );
  expect(api.advanceCadence).not.toHaveBeenCalled();
});
it('discards an old company response and aborts its request', async () => {
  let resolve;
  api.cadence.mockImplementationOnce(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  api.cadence.mockResolvedValue({
    data: {
      id: 19,
      revision: 1,
      state: 'stopped',
      book_name: 'Current company',
      steps: [],
    },
  });
  wrapper = mount(ReviewedCadencePanel, {
    props: { accountId: '7', cadenceId: 18 },
  });
  const options = api.cadence.mock.calls[0][2];
  await wrapper.setProps({ accountId: '8', cadenceId: 19 });
  resolve({
    data: {
      id: 18,
      revision: 3,
      state: 'active',
      book_name: 'Previous company',
      steps: [],
    },
  });
  await flushPromises();
  expect(options.signal.aborted).toBe(true);
  expect(wrapper.text()).toContain('Current company');
  expect(wrapper.text()).not.toContain('Previous company');
});
