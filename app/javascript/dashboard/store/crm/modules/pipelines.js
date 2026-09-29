/* eslint-disable no-console */
import { pipelinesAPI } from '../../../api/crm';

export default {
  namespaced: true,
  state: {
    pipelines: [],
    isLoading: false,
    error: null,
  },
  getters: {
    allPipelines: state => state.pipelines,
    isLoading: state => state.isLoading,
    error: state => state.error,
  },
  mutations: {
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
    async fetchPipelines({ commit }) {
      commit('SET_LOADING', true);
      commit('SET_ERROR', null);
      commit('SET_PIPELINES', []);
      try {
        const response = await pipelinesAPI.list();
        commit('SET_PIPELINES', response.data);
      } catch (error) {
        commit(
          'SET_ERROR',
          error.response?.data?.error || 'Não foi possível carregar os funis.'
        );
      } finally {
        commit('SET_LOADING', false);
      }
    },
  },
};
