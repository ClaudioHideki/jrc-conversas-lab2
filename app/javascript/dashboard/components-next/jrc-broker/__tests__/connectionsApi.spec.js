import { createJrcBrokerApi } from 'dashboard/api/jrcBroker';

afterEach(() => vi.unstubAllGlobals());

it('reads connection metrics on the captured account and encodes the inbox path', async () => {
  const request = vi.fn().mockResolvedValue({ data: { metrics: null } });
  vi.stubGlobal('axios', request);
  const signal = new AbortController().signal;
  await createJrcBrokerApi(7).connectionSummary('12/other', signal);
  expect(request).toHaveBeenCalledWith({
    method: 'get',
    url: '/api/v1/accounts/7/jrc_broker/inboxes/12%2Fother/summary',
    data: undefined,
    signal,
    headers: {},
  });
});

it('loads inboxes from the authenticated Rails origin and retains the captured account', async () => {
  const request = vi.fn().mockResolvedValue({ data: { payload: [] } });
  vi.stubGlobal('axios', request);
  const first = createJrcBrokerApi(1);
  const second = createJrcBrokerApi(2);
  const signal = new AbortController().signal;
  await second.inboxes(signal);
  await first.inboxes(signal);
  expect(request.mock.calls.map(([value]) => value.url)).toEqual([
    '/api/v1/accounts/2/inboxes',
    '/api/v1/accounts/1/inboxes',
  ]);
  expect(request).toHaveBeenLastCalledWith({
    method: 'get',
    url: '/api/v1/accounts/1/inboxes',
    signal,
  });
});

it('reads the pairing operation through the captured inbox and account without replaying a mutation', async () => {
  const request = vi.fn().mockResolvedValue({ data: { state: 'PENDING' } });
  vi.stubGlobal('axios', request);
  const signal = new AbortController().signal;
  await createJrcBrokerApi(7).pairOperation(
    12,
    '11111111-1111-4111-8111-111111111111',
    signal
  );
  expect(request).toHaveBeenCalledWith({
    method: 'get',
    url: '/api/v1/accounts/7/jrc_broker/inboxes/12/pair-operations/11111111-1111-4111-8111-111111111111',
    data: undefined,
    signal,
    headers: {},
  });
});
