import proposalsAPI from '../proposals';

it('uses the account-scoped authenticated axios client with a blob response', async () => {
  window.history.replaceState({}, '', '/app/accounts/7/crm/proposals');
  global.axios = {
    get: vi.fn().mockResolvedValue({ data: new Blob(['%PDF']) }),
  };
  await proposalsAPI.pdf(12);
  expect(global.axios.get).toHaveBeenCalledWith(
    '/api/v1/accounts/7/crm/proposals/12/pdf',
    { responseType: 'blob' }
  );
});
