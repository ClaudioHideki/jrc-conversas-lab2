/* eslint-disable no-console */
import { leadsAPI } from '../../../api/crm';
import { authorityScope, hasCurrentAuthority } from '../authorityScope';

export default {
  namespaced: true,
  state: {
    listRequestId: 0,
    authorityScope: null,
    leads: [],
    currentLead: null,
    detailScope: null,
    detailRequestId: 0,
    detailLoading: false,
    filters: {},
    isLoading: false,
    pagination: {},
  },
  getters: {
    allLeads: (state, _getters, _rootState, rootGetters) =>
      hasCurrentAuthority(state, rootGetters) ? state.leads : [],
    leadById: (_state, getters) => id =>
      getters.allLeads.find(l => l.id === id),
    currentLead: (state, _getters, _rootState, rootGetters) =>
      state.detailScope === authorityScope(rootGetters)
        ? state.currentLead
        : null,
    isLoading: (state, _getters, _rootState, rootGetters) =>
      (hasCurrentAuthority(state, rootGetters) && state.isLoading) ||
      (state.detailScope === authorityScope(rootGetters) &&
        state.detailLoading),
  },
  mutations: {
    SET_AUTHORITY_SCOPE(state, value) {
      state.authorityScope = value;
    },
    SET_LIST_REQUEST_ID(state, value) {
      state.listRequestId = value;
    },
    SET_LEADS(state, payload) {
      state.leads = payload;
    },
    START_DETAIL_REQUEST(state, scope) {
      state.detailScope = scope;
      state.detailRequestId += 1;
      state.currentLead = null;
      state.detailLoading = false;
    },
    SET_DETAIL_LOADING(state, value) {
      state.detailLoading = value;
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
    async fetchLeads({ commit, state, rootGetters }, params) {
      const requestId = state.listRequestId + 1;
      commit('SET_LIST_REQUEST_ID', requestId);
      const scope = authorityScope(rootGetters);
      commit('SET_AUTHORITY_SCOPE', scope);
      commit('SET_LEADS', []);
      commit('SET_LOADING', true);
      try {
        const response = await leadsAPI.list(params);
        if (
          requestId !== state.listRequestId ||
          scope !== authorityScope(rootGetters)
        )
          return;
        commit('SET_LEADS', response.data);
      } catch (error) {
        if (
          requestId !== state.listRequestId ||
          scope !== authorityScope(rootGetters)
        )
          return;
        console.error('CRM leads list request failed', {
          status: error.response?.status,
        });
      } finally {
        if (
          requestId === state.listRequestId &&
          scope === authorityScope(rootGetters)
        )
          commit('SET_LOADING', false);
      }
    },
    async fetchLead({ commit, state, rootGetters }, id) {
      const scope = authorityScope(rootGetters);
      commit('START_DETAIL_REQUEST', scope);
      const requestId = state.detailRequestId;
      if (!id) return;
      commit('SET_DETAIL_LOADING', true);
      try {
        const response = await leadsAPI.show(id);
        if (
          requestId !== state.detailRequestId ||
          scope !== authorityScope(rootGetters)
        )
          return;
        commit('SET_CURRENT_LEAD', response.data);
      } catch (error) {
        if (
          requestId !== state.detailRequestId ||
          scope !== authorityScope(rootGetters)
        )
          return;
        console.error('CRM lead detail request failed', {
          status: error.response?.status,
        });
      } finally {
        if (
          requestId === state.detailRequestId &&
          scope === authorityScope(rootGetters)
        )
          commit('SET_DETAIL_LOADING', false);
      }
    },
    async createLead({ dispatch, rootGetters }, data) {
      const scope = authorityScope(rootGetters);
      await leadsAPI.create(data);
      if (scope === authorityScope(rootGetters)) await dispatch('fetchLeads');
    },
    async convertLead({ dispatch, rootGetters }, { leadId, params }) {
      const scope = authorityScope(rootGetters);
      await leadsAPI.convert(leadId, params);
      if (scope === authorityScope(rootGetters)) await dispatch('fetchLeads');
    },
    async loseLead({ dispatch, rootGetters }, { leadId, params }) {
      const scope = authorityScope(rootGetters);
      await leadsAPI.lose(leadId, params);
      if (scope === authorityScope(rootGetters)) await dispatch('fetchLeads');
    },
  },
};
