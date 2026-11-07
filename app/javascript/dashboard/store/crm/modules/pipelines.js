/* eslint-disable no-console */
import { pipelinesAPI } from '../../../api/crm';
import { authorityScope, hasCurrentAuthority } from '../authorityScope';

export default {
  namespaced: true,
  state: {
    listRequestId: 0,
    authorityScope: null,
    pipelines: [],
    isLoading: false,
    error: null,
  },
  getters: {
    allPipelines: (state, _getters, _rootState, rootGetters) =>
      hasCurrentAuthority(state, rootGetters) ? state.pipelines : [],
    isLoading: (state, _getters, _rootState, rootGetters) =>
      hasCurrentAuthority(state, rootGetters) && state.isLoading,
    error: (state, _getters, _rootState, rootGetters) =>
      hasCurrentAuthority(state, rootGetters) ? state.error : null,
  },
  mutations: {
    SET_LIST_REQUEST_ID(state, value) {
      state.listRequestId = value;
    },
    SET_AUTHORITY_SCOPE(state, value) {
      state.authorityScope = value;
    },
    SET_PIPELINES(state, payload) {
      state.pipelines = payload;
    },
    SET_LOADING(state, payload) {
      state.isLoading = payload;
    },
    SET_ERROR(state, payload) {
      state.error = payload;
    },
  },
  actions: {
    async fetchPipelines({ commit, state, rootGetters }) {
      const requestId = state.listRequestId + 1;
      commit('SET_LIST_REQUEST_ID', requestId);
      const scope = authorityScope(rootGetters);
      commit('SET_AUTHORITY_SCOPE', scope);
      commit('SET_LOADING', true);
      commit('SET_ERROR', null);
      commit('SET_PIPELINES', []);
      try {
        const response = await pipelinesAPI.list();
        if (
          requestId !== state.listRequestId ||
          scope !== authorityScope(rootGetters)
        )
          return;
        commit('SET_PIPELINES', response.data);
      } catch (error) {
        if (
          requestId !== state.listRequestId ||
          scope !== authorityScope(rootGetters)
        )
          return;
        commit(
          'SET_ERROR',
          error.response?.data?.error || 'Não foi possível carregar os funis.'
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
