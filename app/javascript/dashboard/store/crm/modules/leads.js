/* eslint-disable no-console */
import { leadsAPI } from '../../../api/crm';

export default {
  namespaced: true,
  state: {
    listRequestId: 0,
    leads: [],
    currentLead: null,
    filters: {},
    isLoading: false,
    pagination: {},
  },
  getters: {
    allLeads: state => state.leads,
    leadById: state => id => state.leads.find(l => l.id === id),
    isLoading: state => state.isLoading,
  },
  mutations: {
    SET_LIST_REQUEST_ID(state, value) {
      state.listRequestId = value;
    },
    SET_LEADS(state, payload) {
      state.leads = payload;
    },
    SET_CURRENT_LEAD(state, payload) {
      state.currentLead = payload;
    },
    SET_LOADING(state, payload) {
      state.isLoading = payload;
    },
    SET_FILTERS(state, payload) {
      state.filters = payload;
    },
  },
  actions: {
    async fetchLeads({ commit, state }, params) {
      const requestId = state.listRequestId + 1;
      commit('SET_LIST_REQUEST_ID', requestId);
      commit('SET_LEADS', []);
      commit('SET_LOADING', true);
      try {
        const response = await leadsAPI.list(params);
        if (requestId !== state.listRequestId) return;
        commit('SET_LEADS', response.data);
      } catch (error) {
        if (requestId !== state.listRequestId) return;
        console.error(error);
      } finally {
        if (requestId === state.listRequestId) commit('SET_LOADING', false);
      }
    },
    async fetchLead({ commit }, id) {
      commit('SET_LOADING', true);
      try {
        const response = await leadsAPI.show(id);
        commit('SET_CURRENT_LEAD', response.data);
      } catch (error) {
        console.error(error);
      } finally {
        commit('SET_LOADING', false);
      }
    },
    async createLead({ dispatch }, data) {
      await leadsAPI.create(data);
      dispatch('fetchLeads');
    },
    async convertLead({ dispatch }, { leadId, params }) {
      await leadsAPI.convert(leadId, params);
      dispatch('fetchLeads');
    },
    async loseLead({ dispatch }, { leadId, params }) {
      await leadsAPI.lose(leadId, params);
      dispatch('fetchLeads');
    },
  },
};
