import ConversationListAPI from '../inbox/conversation';
import ConversationAPI from '../conversations';
import VoiceAPI from '../jrcContactCenter';

describe('bounded attendance bootstrap requests', () => {
  const original = global.axios;
  beforeEach(() => {
    global.axios = { get: vi.fn().mockResolvedValue({ data: {} }) };
  });
  afterEach(() => {
    global.axios = original;
  });

  it.each([
    [
      'conversation page',
      () => ConversationListAPI.get({ page: 1, status: 'open' }),
    ],
    ['sharing scope', () => ConversationAPI.sharedContext(1)],
    ['voice list', () => VoiceAPI.calls(1, { limit: 50 })],
    ['voice capabilities', () => VoiceAPI.context(1)],
  ])(
    'bounds %s so the existing error/retry state can replace an endless spinner',
    async (_name, request) => {
      await request();
      expect(global.axios.get.mock.calls[0][1].timeout).toBe(30000);
    }
  );
});
