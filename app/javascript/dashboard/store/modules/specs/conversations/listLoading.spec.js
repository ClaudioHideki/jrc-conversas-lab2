import axios from 'axios';
import { createStore } from 'vuex';
import { ref } from 'vue';
import conversations from '../../conversations';
import conversationPage from '../../conversationPage';
import types from '../../../mutation-types';

vi.mock('axios');
global.axios = axios;

describe('conversation list request lifecycle with a real Vuex store', () => {
  let store;
  let accountId;
  let setContacts;

  beforeEach(() => {
    accountId = ref(1);
    setContacts = vi.fn();
    store = createStore({
      state: {
        ...conversations.state,
        allConversations: [],
        conversationFilters: { assigneeType: 'all', status: 'open', page: 1 },
        listLoadingStatus: false,
      },
      getters: {
        ...conversations.getters,
        getCurrentAccountId: () => accountId.value,
      },
      mutations: conversations.mutations,
      actions: conversations.actions,
      modules: {
        conversationPage: {
          ...conversationPage,
          state: {
            currentPage: { all: 0, me: 0, appliedFilters: 0 },
            hasEndReached: { all: false, me: false, appliedFilters: false },
          },
        },
        contacts: {
          namespaced: true,
          mutations: { SET_CONTACTS: setContacts },
        },
        conversationStats: { namespaced: true, actions: { set: vi.fn() } },
        conversationLabels: {
          namespaced: true,
          actions: { setBulkConversationLabels: vi.fn() },
        },
      },
    });
  });

  it('accepts a valid response after reactive filters are replaced by equivalent values', async () => {
    let resolve;
    axios.get.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const pending = store.dispatch('fetchAllConversations');
    await store.dispatch('updateChatListFilters', {
      ...store.state.conversationFilters,
    });
    resolve({
      data: {
        data: {
          payload: [{ id: 101, meta: { sender: { id: 2 } } }],
          meta: { all_count: 1 },
        },
      },
    });
    await pending;
    expect(store.state.allConversations.map(c => c.id)).toEqual([101]);
    expect(store.state.listLoadingStatus).toBe(false);
    expect(store.state.conversationPage.currentPage.all).toBe(1);
  });

  it.each([403, 500])(
    'ends loading and exposes a generic error after HTTP %s',
    async status => {
      axios.get.mockRejectedValueOnce({
        response: { status, data: { error: 'private backend detail' } },
      });
      await store.dispatch('fetchAllConversations');
      expect(store.state.listLoadingStatus).toBe(false);
      expect(store.getters.getChatListErrorStatus).toBe(true);
      expect(store.state.allConversations).toEqual([]);
      expect(JSON.stringify(store.state)).not.toContain(
        'private backend detail'
      );
      expect(store.state.conversationPage.hasEndReached.all).toBe(false);
    }
  );

  it('allows an explicit retry to recover from a failed request', async () => {
    axios.get.mockRejectedValueOnce(new Error('network unavailable'));
    await store.dispatch('fetchAllConversations');
    expect(store.getters.getChatListErrorStatus).toBe(true);
    axios.get.mockResolvedValueOnce({
      data: { data: { payload: [], meta: { all_count: 0 } } },
    });
    await store.dispatch('fetchAllConversations');
    expect(store.state.listLoadingStatus).toBe(false);
    expect(store.getters.getChatListErrorStatus).toBe(false);
    expect(store.state.conversationPage.hasEndReached.all).toBe(true);
  });

  it('ignores an older request with identical filters after the newer response has arrived', async () => {
    let resolveOlder;
    axios.get.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolveOlder = done;
        })
    );
    const older = store.dispatch('fetchAllConversations');
    axios.get.mockResolvedValueOnce({
      data: {
        data: { payload: [{ id: 102, meta: { sender: { id: 2 } } }], meta: {} },
      },
    });
    await store.dispatch('fetchAllConversations');
    resolveOlder({
      data: {
        data: { payload: [{ id: 101, meta: { sender: { id: 2 } } }], meta: {} },
      },
    });
    await older;
    expect(store.state.allConversations.map(c => c.id)).toEqual([102]);
    expect(store.state.listLoadingStatus).toBe(false);
  });

  it('does not let an older failure stop the current request or display its error', async () => {
    let rejectOlder;
    let resolveNewer;
    axios.get.mockImplementationOnce(
      () =>
        new Promise((_done, reject) => {
          rejectOlder = reject;
        })
    );
    const older = store.dispatch('fetchAllConversations');
    axios.get.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolveNewer = done;
        })
    );
    const newer = store.dispatch('fetchAllConversations');
    rejectOlder(new Error('old failure'));
    await older;
    expect(store.state.listLoadingStatus).toBe(true);
    expect(store.getters.getChatListErrorStatus).toBe(false);
    resolveNewer({ data: { data: { payload: [], meta: {} } } });
    await newer;
    expect(store.state.listLoadingStatus).toBe(false);
  });

  it('discards data and errors from the previous Account', async () => {
    let resolve;
    axios.get.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const pending = store.dispatch('fetchAllConversations');
    accountId.value = 2;
    resolve({
      data: {
        data: {
          payload: [{ id: 101, account_id: 1, meta: { sender: { id: 2 } } }],
          meta: {},
        },
      },
    });
    await pending;
    expect(store.state.allConversations).toEqual([]);
    expect(store.state.listLoadingStatus).toBe(true);
  });

  it('discards changed filters while ending loading when no newer request owns the list', async () => {
    let resolve;
    axios.get.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const pending = store.dispatch('fetchAllConversations');
    store.commit(types.UPDATE_CHAT_LIST_FILTERS, { assigneeType: 'me' });
    resolve({
      data: {
        data: { payload: [{ id: 101, meta: { sender: { id: 2 } } }], meta: {} },
      },
    });
    await pending;
    expect(store.state.allConversations).toEqual([]);
    expect(store.state.listLoadingStatus).toBe(false);
  });

  it('ends loading after a filtered list fails without treating it as an empty result', async () => {
    axios.post.mockRejectedValueOnce(new Error('filter failed'));
    await store.dispatch('fetchFilteredConversations', {
      queryData: { payload: [] },
      page: 1,
    });
    expect(store.state.listLoadingStatus).toBe(false);
    expect(store.getters.getChatListErrorStatus).toBe(true);
    expect(store.state.conversationPage.hasEndReached.appliedFilters).toBe(
      false
    );
  });

  it('discards filtered results from the previous Account without adding contacts', async () => {
    let resolve;
    axios.post.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const pending = store.dispatch('fetchFilteredConversations', {
      queryData: { payload: [] },
      page: 1,
    });
    accountId.value = 2;
    resolve({
      data: {
        payload: [{ id: 101, account_id: 1, meta: { sender: { id: 2 } } }],
        meta: {},
      },
    });
    await pending;
    expect(store.state.allConversations).toEqual([]);
    expect(store.state.conversationPage.currentPage.appliedFilters).toBe(0);
    expect(setContacts).not.toHaveBeenCalled();
    expect(store.getters.getChatListErrorStatus).toBe(false);
  });

  it('does not let an older filtered response overwrite a newer regular list', async () => {
    let resolve;
    axios.post.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const older = store.dispatch('fetchFilteredConversations', {
      queryData: { payload: [] },
      page: 1,
    });
    axios.get.mockResolvedValueOnce({
      data: {
        data: { payload: [{ id: 102, meta: { sender: { id: 3 } } }], meta: {} },
      },
    });
    await store.dispatch('fetchAllConversations');
    resolve({
      data: { payload: [{ id: 101, meta: { sender: { id: 2 } } }], meta: {} },
    });
    await older;
    expect(store.state.allConversations.map(c => c.id)).toEqual([102]);
    expect(store.state.listLoadingStatus).toBe(false);
    expect(store.state.conversationPage.currentPage.appliedFilters).toBe(0);
  });
});
