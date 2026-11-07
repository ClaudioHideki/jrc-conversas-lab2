/* eslint-disable no-console */
import { proposalsAPI } from '../../../api/crm';

const authorityScope = getters =>
  JSON.stringify([
    getters.getCurrentAccountId,
    getters.getCurrentUserID,
    getters.getCurrentRole,
    getters.getCurrentUser?.accounts,
  ]);

export default {
  namespaced: true,
  state: {
    listRequestId: 0,
    authorityScope: null,
    proposals: [],
    filters: {},
    isLoading: false,
    pagination: {},
    error: null,
  },
  getters: {
    allProposals: (state, _getters, _rootState, rootGetters) =>
      state.authorityScope === authorityScope(rootGetters)
        ? state.proposals
        : [],
    isLoading: (state, _getters, _rootState, rootGetters) =>
      state.authorityScope === authorityScope(rootGetters) && state.isLoading,
    error: (state, _getters, _rootState, rootGetters) =>
      state.authorityScope === authorityScope(rootGetters) ? state.error : null,
  },
  mutations: {
    SET_AUTHORITY_SCOPE(state, value) {
      state.authorityScope = value;
    },
    SET_LIST_REQUEST_ID(state, value) {
      state.listRequestId = value;
    },
    SET_PROPOSALS(state, payload) {
      state.proposals = payload;
    },
    SET_LOADING(state, payload) {
      state.isLoading = payload;
    },
    SET_ERROR(state, payload) {
      state.error = payload;
    },
  },
  actions: {
    async fetchProposals({ commit, state, rootGetters }, params) {
      const requestId = state.listRequestId + 1;
      const scope = authorityScope(rootGetters);
      commit('SET_LIST_REQUEST_ID', requestId);
      commit('SET_AUTHORITY_SCOPE', scope);
      commit('SET_PROPOSALS', []);
      commit('SET_LOADING', true);
      commit('SET_ERROR', null);
      try {
        const response = await proposalsAPI.list(params);
        if (
          requestId !== state.listRequestId ||
          scope !== authorityScope(rootGetters)
        )
          return;
        commit('SET_PROPOSALS', response.data);
      } catch (error) {
        if (
          requestId !== state.listRequestId ||
          scope !== authorityScope(rootGetters)
        )
          return;
        console.error('CRM proposals list request failed', {
          status: error.response?.status,
        });
        commit(
          'SET_ERROR',
          error.response?.data?.error ||
            'Não foi possível carregar as propostas.'
        );
      } finally {
        if (
          requestId === state.listRequestId &&
          scope === authorityScope(rootGetters)
        )
          commit('SET_LOADING', false);
      }
    },
  },
};
