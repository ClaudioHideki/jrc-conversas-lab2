import { createServiceDeskOperationsClient } from '../serviceDeskOperationsClient';

let http;
let client;
const input = () => ({
  unit_id: '2',
  requestKey: 'synthetic-native-recording-key',
  ticket: {
    title: 'SYNTHETIC native intake',
    description: 'SYNTHETIC details',
    requester_id: '3',
  },
});

beforeEach(() => {
  http = {
    get: vi.fn(),
    post: vi.fn().mockResolvedValue({ data: { applied: true } }),
    patch: vi.fn(),
  };
  client = createServiceDeskOperationsClient(http);
});

it('preserves the ordinary native intake contract when no recording is selected', async () => {
  const payload = input();
  await client.create('1', payload);
  expect(http.post).toHaveBeenCalledWith(
    '/api/v1/accounts/1/jrc_service_desk/tickets',
    { unit_id: '2', ticket: payload.ticket },
    expect.objectContaining({
      headers: { 'Idempotency-Key': payload.requestKey },
    })
  );
});

it('transports only the explicit recording identifier alongside the existing native request and key', async () => {
  const payload = { ...input(), recording_id: '8' };
  await client.create('1', payload);
  expect(http.post).toHaveBeenCalledWith(
    '/api/v1/accounts/1/jrc_service_desk/tickets',
    { unit_id: '2', ticket: payload.ticket, recording_id: '8' },
    expect.objectContaining({
      headers: { 'Idempotency-Key': payload.requestKey },
    })
  );
});

it.each([undefined, null, '', 0, false, ['8'], { id: '8' }, '8suffix'])(
  'rejects a malformed selected source rather than silently creating an unrelated ordinary ticket: %s',
  recordingId => {
    expect(() =>
      client.create('1', { ...input(), recording_id: recordingId })
    ).toThrow(TypeError);
    expect(http.post).not.toHaveBeenCalled();
  }
);

it('keeps the source identifier in the existing native multipart upload transport', async () => {
  const payload = {
    ...input(),
    recording_id: '8',
    files: [new File(['SYNTHETIC'], 'synthetic.txt', { type: 'text/plain' })],
  };
  await client.create('1', payload);
  const body = http.post.mock.calls[0][1];
  expect(body).toBeInstanceOf(FormData);
  expect(body.get('recording_id')).toBe('8');
  expect(JSON.parse(body.get('ticket'))).toEqual(payload.ticket);
  expect(body.getAll('files[]')).toHaveLength(1);
});

it('rejects forged origin or actor authority before touching the HTTP client', () => {
  expect(() =>
    client.create('1', {
      ...input(),
      recording_origin: { recording_id: '8' },
      user_id: '4',
    })
  ).toThrow(TypeError);
  expect(http.post).not.toHaveBeenCalled();
});
