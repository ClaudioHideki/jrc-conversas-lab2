/* eslint-disable no-console */
import { activitiesAPI } from '../../../api/crm';
import { authorityScope, hasCurrentAuthority } from '../authorityScope';

export default {
  namespaced: true,
  state: {
    listRequestId: 0,
    authorityScope: null,
    activities: [],
    filters: {},
    isLoading: false,
    pagination: {},
    error: null,
  },
  getters: {
    allActivities: (state, _getters, _rootState, rootGetters) =>
      hasCurrentAuthority(state, rootGetters) ? state.activities : [],
    isLoading: (state, _getters, _rootState, rootGetters) =>
      hasCurrentAuthority(state, rootGetters) && state.isLoading,
    error: (state, _getters, _rootState, rootGetters) =>
      hasCurrentAuthority(state, rootGetters) ? state.error : null,
  },
  mutations: {
    SET_AUTHORITY_SCOPE(state, value) {
      state.authorityScope = value;
    },
    SET_LIST_REQUEST_ID(state, value) {
      state.listRequestId = value;
    },
    SET_ACTIVITIES(state, payload) {
      state.activities = payload;
    },
    SET_LOADING(state, payload) {
      state.isLoading = payload;
    },
    SET_ERROR(state, payload) {
      state.error = payload;
    },
  },
  actions: {
    async fetchActivities({ commit, state, rootGetters }, params) {
      const requestId = state.listRequestId + 1;
      commit('SET_LIST_REQUEST_ID', requestId);
      const scope = authorityScope(rootGetters);
      commit('SET_AUTHORITY_SCOPE', scope);
      commit('SET_ACTIVITIES', []);
      commit('SET_LOADING', true);
      commit('SET_ERROR', null);
      try {
        const response = await activitiesAPI.list(params);
        if (
          requestId !== state.listRequestId ||
          scope !== authorityScope(rootGetters)
        )
          return;
        commit('SET_ACTIVITIES', response.data);
      } catch (error) {
        if (
          requestId !== state.listRequestId ||
          scope !== authorityScope(rootGetters)
        )
          return;
        console.error('CRM activities list request failed', {
          status: error.response?.status,
        });
        commit(
          'SET_ERROR',
          error.response?.data?.error ||
            'Não foi possível carregar as atividades.'
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
