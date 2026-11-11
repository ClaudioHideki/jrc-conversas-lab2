import MessageApi from 'dashboard/api/inbox/message';
import actions from '../../conversations/actions';
import types from '../../../mutation-types';

vi.mock('dashboard/api/inbox/message', () => ({
  default: { retry: vi.fn(), create: vi.fn() },
}));

const failed = {
  id: 101,
  conversation_id: 202,
  content: 'Synthetic message',
  status: 'failed',
  content_attributes: { external_error: '131049: Synthetic restriction' },
};

describe('WhatsApp retry result', () => {
  it('does not replace a truthful failed API response with sent', async () => {
    const commit = vi.fn();
    MessageApi.retry.mockResolvedValue({ data: failed });
    await actions.sendMessageWithData({ commit }, failed);
    expect(commit).toHaveBeenLastCalledWith(types.ADD_CONVERSATION_ATTACHMENTS, failed);
    expect(commit.mock.calls.filter(([type]) => type === types.ADD_MESSAGE).at(-1)[1].status).toBe('failed');
  });

  it('keeps the previous failure visible while a retry request is pending', async () => {
    const commit = vi.fn();
    MessageApi.retry.mockResolvedValue({ data: failed });
    await actions.sendMessageWithData({ commit }, failed);
    expect(commit.mock.calls[0][1].status).toBe('failed');
  });

  it('preserves original evidence and exposes the server explanation on a denied request', async () => {
    const commit = vi.fn();
    const error = { response: { data: { error: 'Retry blocked for review', retry: { status: 'blocked' } } } };
    MessageApi.retry.mockRejectedValue(error);
    await expect(actions.sendMessageWithData({ commit }, failed)).rejects.toEqual(error);
    const result = commit.mock.calls.at(-1)[1];
    expect(result.status).toBe('failed');
    expect(result.content_attributes).toEqual(failed.content_attributes);
    expect(result.meta.error).toBe('Retry blocked for review');
  });

  it('preserves the existing creation flow for a local network failure', async () => {
    const commit = vi.fn();
    const pending = { ...failed, content_attributes: {} };
    MessageApi.create.mockResolvedValue({ data: { ...pending, status: 'sent' } });
    await actions.sendMessageWithData({ commit }, pending);
    expect(MessageApi.create).toHaveBeenCalledWith(pending);
    expect(MessageApi.retry).not.toHaveBeenCalled();
    expect(commit.mock.calls[0][1].status).toBe('progress');
  });
});
