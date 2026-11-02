import { describe, expect, it } from 'vitest';
import { createMemoryHistory, createRouter } from 'vue-router';
import { canReturnToAccountList } from '../listReturn';
const router = createRouter({
  history: createMemoryHistory(),
  routes: [
    {
      path: '/app/accounts/:accountId/contacts',
      name: 'contacts_dashboard_index',
      component: {},
    },
    {
      path: '/app/accounts/:accountId/contacts/:id',
      name: 'contacts_edit',
      component: {},
    },
    {
      path: '/app/accounts/:accountId/companies',
      name: 'companies_dashboard_index',
      component: {},
    },
  ],
});
describe('scoped list return navigation', () => {
  it('preserves the previous list page/filter instead of replacing it with page one', () => {
    const back = '/app/accounts/1/contacts?page=7&search=synthetic';
    expect(
      canReturnToAccountList(router, 1, ['contacts_dashboard_index'], back)
    ).toBe(true);
    expect(router.resolve(back).query).toEqual({
      page: '7',
      search: 'synthetic',
    });
  });
  it.each([
    undefined,
    '',
    'https://outside.invalid',
    '//outside.invalid',
    '/app/accounts/2/contacts',
    '/app/accounts/1/companies',
    '/app/accounts/1/contacts/55',
  ])(
    'does not return a contact list action to an unrelated or foreign destination %s',
    back =>
      expect(
        canReturnToAccountList(router, 1, ['contacts_dashboard_index'], back)
      ).toBe(false)
  );
  it('accepts only the native company list for the company return action', () => {
    expect(
      canReturnToAccountList(
        router,
        1,
        ['companies_dashboard_index'],
        '/app/accounts/1/companies?page=5'
      )
    ).toBe(true);
    expect(
      canReturnToAccountList(
        router,
        1,
        ['companies_dashboard_index'],
        '/app/accounts/1/contacts?page=5'
      )
    ).toBe(false);
  });
});
