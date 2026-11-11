import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import conversationsAPI from '../conversations';
import inboxAPI from '../inbox/conversation';

let originalAxios;
let get;
beforeEach(() => {
  originalAxios = window.axios;
  get = vi.fn().mockResolvedValue({ data: {} });
  window.axios = { get };
});
afterEach(() => {
  window.axios = originalAxios;
});

it('sends member scope consistently for the list and count requests', () => {
  inboxAPI.get({ assigneeType: 'me', inboxScope: 'member', status: 'all' });
  inboxAPI.meta({ assigneeType: 'me', inboxScope: 'member', status: 'all' });
  conversationsAPI.sharedContext(1, 'member');
  expect(
    get.mock.calls.map(([, options]) => options.params.inbox_scope)
  ).toEqual(['member', 'member', 'member']);
  expect(get.mock.calls[0][1].params).toMatchObject({
    assignee_type: 'me',
    status: 'all',
  });
  expect(get.mock.calls[2][0]).toBe('/api/v1/accounts/1/conversations/meta');
});

it('leaves the pre-existing API request scope unchanged when it was not requested', () => {
  inboxAPI.get({ assigneeType: 'me' });
  inboxAPI.meta({ assigneeType: 'all' });
  conversationsAPI.sharedContext(1);
  expect(
    get.mock.calls.every(
      ([, options]) => options.params.inbox_scope === undefined
    )
  ).toBe(true);
});
