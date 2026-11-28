import { mutations } from '../index';
import types from '../../../mutation-types';
import actions from '../actions';
import ConversationApi from '../../../../api/inbox/conversation';
import { createStore } from 'vuex';
import conversations from '../index';
import notifications from '../../notifications';
import contactConversations from '../../contactConversations';
import conversationMetadata from '../../conversationMetadata';
import conversationSearch from '../../conversationSearch';

it('preserves loaded attachments through a failed refresh and accepts a later empty response', async () => {
  const cached = [{ id: 53 }];
  const state = { attachments: { 11: cached } };
  const context = {
    state,
    commit: (type, payload) => mutations[type](state, payload),
    rootGetters: { getCurrentAccountId: 1 },
  };
  const request = vi.spyOn(ConversationApi, 'getAllAttachments');
  try {
    request.mockRejectedValueOnce(new Error('network disconnected'));
    await actions.fetchAllAttachments(context, 11);
    expect(state.attachments[11]).toEqual(cached);

    request.mockResolvedValueOnce({ data: { payload: [] } });
    await actions.fetchAllAttachments(context, 11);
    expect(state.attachments[11]).toEqual([]);
  } finally {
    request.mockRestore();
  }
});

it('revokes cached conversation access when an attachment refresh is denied', async () => {
  const request = vi
    .spyOn(ConversationApi, 'getAllAttachments')
    .mockRejectedValue({ response: { status: 403 } });
  const dispatch = vi.fn();
  try {
    await actions.fetchAllAttachments(
      { state: {}, commit: vi.fn(), dispatch },
      11
    );
    expect(dispatch).toHaveBeenCalledWith('revokeConversationAccess', 11);
  } finally {
    request.mockRestore();
  }
});

it('purges the selected conversation and its private cached data after access revocation', () => {
  const state = {
    allConversations: [
      { id: 11, messages: [{ content: 'private' }] },
      { id: 22 },
    ],
    attachments: { 11: [{ url: 'private-file' }], 22: [] },
    selectedChatId: 11,
    conversationParticipants: [{ id: 5 }],
    syncConversationsMessages: { 11: [{ content: 'pending' }] },
  };
  mutations[types.DELETE_CONVERSATION](state, 11);
  expect(state.allConversations).toEqual([{ id: 22 }]);
  expect(state.attachments).toEqual({ 22: [] });
  expect(state.selectedChatId).toBeNull();
  expect(state.conversationParticipants).toEqual([]);
  expect(state.syncConversationsMessages).toEqual({});
});

it('purges related notification, contact-history and conversation metadata caches', async () => {
  const store = createStore({
    modules: {
      conversations: {
        ...conversations,
        state: { ...conversations.state, allConversations: [{ id: 11 }] },
      },
      notifications: {
        ...notifications,
        state: {
          ...notifications.state,
          records: { 9: { primary_actor: { content: 'private' } } },
        },
      },
      contactConversations: {
        ...contactConversations,
        state: { ...contactConversations.state, records: { 7: [{ id: 11 }] } },
      },
      conversationMetadata: {
        ...conversationMetadata,
        state: { records: { 11: { private: 'old context' } } },
      },
      conversationSearch: {
        ...conversationSearch,
        state: {
          ...conversationSearch.state,
          records: [{ content: 'old message' }],
          messageRecords: [{ content: 'old message' }],
        },
      },
    },
  });
  await store.dispatch('revokeConversationAccess', 11);
  expect(store.state.notifications.records).toEqual({});
  expect(store.state.contactConversations.records).toEqual({});
  expect(store.state.conversationMetadata.records).toEqual({});
  expect(store.state.conversationSearch.records).toEqual([]);
  expect(store.state.conversationSearch.messageRecords).toEqual([]);
});

it('discards an attachment response that was already in flight when access was revoked', async () => {
  let resolve;
  vi.spyOn(ConversationApi, 'getAllAttachments').mockReturnValue(
    new Promise(done => {
      resolve = done;
    })
  );
  const state = {
    allConversations: [{ id: 11 }],
    attachments: {},
    selectedChatId: 11,
    syncConversationsMessages: {},
  };
  const context = {
    state,
    commit: (type, payload) => mutations[type](state, payload),
    dispatch: vi.fn(),
    rootGetters: { getCurrentAccountId: 1 },
  };
  const pending = actions.fetchAllAttachments(context, 11);
  actions.revokeConversationAccess(context, 11);
  resolve({ data: { payload: [{ url: 'private-file' }] } });
  await pending;
  expect(state.attachments).toEqual({});
  vi.restoreAllMocks();
});
