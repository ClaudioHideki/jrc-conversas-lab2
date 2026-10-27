import { mutations } from '../index';
import types from '../../../mutation-types';

describe('incoming message identity and replay', () => {
  it('keeps one conversation when the API and websocket repeat its ID', () => {
    const state = { allConversations: [], selectedChatId: null };
    const conversation = { id: 901, inbox_id: 4, messages: [] };
    mutations[types.SET_ALL_CONVERSATION](state, [conversation]);
    mutations[types.ADD_CONVERSATION](state, { ...conversation });
    mutations[types.SET_ALL_CONVERSATION](state, [{ ...conversation }]);
    expect(state.allConversations.map(row => row.id)).toEqual([901]);
  });

  it('preserves two distinct conversations with identical names and previews', () => {
    const state = { allConversations: [], selectedChatId: null };
    const row = {
      inbox_id: 4,
      meta: { sender: { name: 'Synthetic contact' } },
      messages: [{ content: '23456' }],
    };
    mutations[types.SET_ALL_CONVERSATION](state, [
      { ...row, id: 901 },
      { ...row, id: 902 },
    ]);
    expect(state.allConversations.map(conversation => conversation.id)).toEqual(
      [901, 902]
    );
  });

  it('replaces a repeated websocket message by ID without adding a bubble', () => {
    const state = {
      allConversations: [{ id: 901, messages: [] }],
      selectedChatId: null,
    };
    const message = {
      id: 31,
      conversation_id: 901,
      content: '23456',
      created_at: 100,
    };
    mutations[types.ADD_MESSAGE](state, message);
    mutations[types.ADD_MESSAGE](state, { ...message, status: 'delivered' });
    expect(state.allConversations[0].messages).toEqual([
      { ...message, status: 'delivered' },
    ]);
  });

  it('keeps legitimate identical text under different message IDs', () => {
    const state = {
      allConversations: [{ id: 901, messages: [] }],
      selectedChatId: null,
    };
    mutations[types.ADD_MESSAGE](state, {
      id: 31,
      conversation_id: 901,
      content: '23456',
    });
    mutations[types.ADD_MESSAGE](state, {
      id: 32,
      conversation_id: 901,
      content: '23456',
    });
    expect(
      state.allConversations[0].messages.map(message => message.id)
    ).toEqual([31, 32]);
  });

  it('does not duplicate overlapping history or overwrite a newer websocket update', () => {
    const current = {
      id: 32,
      conversation_id: 901,
      content: '23456',
      status: 'read',
    };
    const state = {
      allConversations: [{ id: 901, messages: [current] }],
      selectedChatId: null,
    };
    const page = [
      { id: 31, conversation_id: 901, content: '23456' },
      { ...current, status: 'sent' },
    ];
    mutations[types.SET_PREVIOUS_CONVERSATIONS](state, { id: 901, data: page });
    mutations[types.SET_PREVIOUS_CONVERSATIONS](state, { id: 901, data: page });
    expect(state.allConversations[0].messages).toEqual([page[0], current]);
  });
});
