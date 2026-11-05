import * as types from '../mutation-types';

const state = {
  records: {},
};

export const getters = {
  getConversationMetadata: $state => id => {
    return $state.records[Number(id)] || {};
  },
};

export const actions = {
  clear({ commit }) {
    commit(types.default.EMPTY_ALL_CONVERSATION);
  },
};

export const mutations = {
  [types.default.EMPTY_ALL_CONVERSATION]($state) {
    $state.records = {};
  },
  [types.default.SET_CONVERSATION_METADATA]: ($state, { id, data }) => {
    $state.records = { ...$state.records, [id]: data };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
