import { createNicoAsyncCompletion } from '../nicoAsyncCompletion';

describe('NICO submitted request completion', () => {
  it('ignores old history, waits for completion and delivers the response only once', () => {
    const tracker = createNicoAsyncCompletion();
    const old = { request_id: 'old', status: 'succeeded', reply: 'Old reply' };
    expect(tracker.consume([old])).toEqual([]);
    tracker.track('new');
    expect(
      tracker.consume([{ request_id: 'new', status: 'planning' }])
    ).toEqual([]);
    const done = { request_id: 'new', status: 'succeeded', reply: 'New reply' };
    expect(tracker.consume([done, old])).toEqual([done]);
    expect(tracker.consume([done])).toEqual([]);
  });

  it('delivers review and failure results without treating them as navigation success', () => {
    const tracker = createNicoAsyncCompletion();
    tracker.track('review');
    tracker.track('failure');
    const commands = [
      {
        request_id: 'review',
        status: 'awaiting_confirmation',
        reply: 'Review this action',
      },
      { request_id: 'failure', status: 'failed', reply: 'Request failed' },
    ];
    expect(tracker.consume(commands)).toEqual(commands);
    expect(tracker.consume(commands)).toEqual([]);
  });

  it('forgets pending completions when the account changes', () => {
    const tracker = createNicoAsyncCompletion();
    tracker.track('request');
    tracker.clear();
    expect(
      tracker.consume([{ request_id: 'request', status: 'succeeded' }])
    ).toEqual([]);
  });
});
