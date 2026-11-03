/* eslint-disable no-console */
import { proposalsAPI } from '../../../api/crm';

export default {
  namespaced: true,
  state: {
    listRequestId: 0,
    proposals: [],
    filters: {},
    isLoading: false,
    pagination: {},
    error: null,
  },
  getters: {
    allProposals: state => state.proposals,
    isLoading: state => state.isLoading,
    error: state => state.error,
  },
  mutations: {
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
    async fetchProposals({ commit, state }, params) {
      const requestId = state.listRequestId + 1;
      commit('SET_LIST_REQUEST_ID', requestId);
      commit('SET_PROPOSALS', []);
      commit('SET_LOADING', true);
      commit('SET_ERROR', null);
      try {
        const response = await proposalsAPI.list(params);
        if (requestId !== state.listRequestId) return;
        commit('SET_PROPOSALS', response.data);
      } catch (error) {
        if (requestId !== state.listRequestId) return;
        console.error(error);
        commit(
          'SET_ERROR',
          error.response?.data?.error ||
            'Não foi possível carregar as propostas.'
        );
      } finally {
        if (requestId === state.listRequestId) commit('SET_LOADING', false);
      }
    },
  },
};
