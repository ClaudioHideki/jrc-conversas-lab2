/* eslint-disable no-console */
import { activitiesAPI } from '../../../api/crm';

export default {
  namespaced: true,
  state: {
    listRequestId: 0,
    activities: [],
    filters: {},
    isLoading: false,
    pagination: {},
    error: null,
  },
  getters: {
    allActivities: state => state.activities,
    isLoading: state => state.isLoading,
    error: state => state.error,
  },
  mutations: {
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
    async fetchActivities({ commit, state }, params) {
      const requestId = state.listRequestId + 1;
      commit('SET_LIST_REQUEST_ID', requestId);
      commit('SET_ACTIVITIES', []);
      commit('SET_LOADING', true);
      commit('SET_ERROR', null);
      try {
        const response = await activitiesAPI.list(params);
        if (requestId !== state.listRequestId) return;
        commit('SET_ACTIVITIES', response.data);
      } catch (error) {
        if (requestId !== state.listRequestId) return;
        console.error(error);
        commit(
          'SET_ERROR',
          error.response?.data?.error ||
            'Não foi possível carregar as atividades.'
        );
      } finally {
        if (requestId === state.listRequestId) commit('SET_LOADING', false);
      }
    },
  },
};
