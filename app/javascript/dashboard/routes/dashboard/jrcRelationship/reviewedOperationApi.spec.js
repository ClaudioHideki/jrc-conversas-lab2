import API from 'dashboard/api/jrcRelationship';
let axios;
beforeEach(() => {
  axios = { get: vi.fn(), post: vi.fn() };
  vi.stubGlobal('axios', axios);
});
it('keeps exact metadata filters and cancellation receipts on native account-scoped routes', async () => {
  const controller = new AbortController();
  const fields = { expected_revision: 3, reason: 'Stop own remaining intent' };
  await API.ownReviewedBatches(
    12,
    { review_id: 51, status: 'all' },
    { signal: controller.signal }
  );
  await API.stopOwnReviewedBatch(12, 51, fields, { signal: controller.signal });
  expect(axios.get).toHaveBeenCalledWith(
    '/api/v1/accounts/12/relationship/reviewed_batches',
    { params: { review_id: 51, status: 'all' }, signal: controller.signal }
  );
  expect(axios.post).toHaveBeenCalledWith(
    '/api/v1/accounts/12/relationship/reviewed_batches/51/cancel_pending',
    fields,
    { signal: controller.signal }
  );
});
it('rejects invalid account contexts before any own-operation request', () => {
  expect(() => API.ownReviewedBatches('12/other', {})).toThrow(
    'Invalid account context'
  );
  expect(() => API.stopOwnReviewedBatch(0, 51, {})).toThrow(
    'Invalid account context'
  );
  expect(axios.get).not.toHaveBeenCalled();
  expect(axios.post).not.toHaveBeenCalled();
});
