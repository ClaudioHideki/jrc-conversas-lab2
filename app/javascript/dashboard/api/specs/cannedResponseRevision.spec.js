import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import API from '../cannedResponse';

let originalAxios;
let get;
beforeEach(() => {
  originalAxios = window.axios;
  get = vi.fn().mockResolvedValue({ data: new Blob(['synthetic']) });
  window.axios = { get };
});
afterEach(() => {
  window.axios = originalAxios;
});

it('sends the reviewed revision and attachment identity with the scoped byte request', async () => {
  const expected = {
    revision: 'synthetic-reviewed-revision',
    attachment_id: 41,
  };
  await API.file(3, 7, expected);
  expect(get).toHaveBeenCalledWith(
    '/api/v1/accounts/7/canned_responses/3/file',
    {
      responseType: 'blob',
      params: expected,
    }
  );
});

it('keeps the existing file consumer compatible when no preview identity was supplied', async () => {
  await API.file(3, 7);
  expect(get).toHaveBeenCalledWith(
    '/api/v1/accounts/7/canned_responses/3/file',
    {
      responseType: 'blob',
      params: {},
    }
  );
});
