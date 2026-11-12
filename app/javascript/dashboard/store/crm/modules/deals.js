/* eslint-disable no-console */

import { dealsAPI, stagesAPI } from '../../../api/crm';
import { authorityScope, hasCurrentAuthority } from '../authorityScope';

export default {
  namespaced: true,

  state: {
    listRequestId: 0,
    authorityScope: null,
    detailScope: null,
    detailRequestId: 0,
    detailLoading: false,
    detailError: null,
    deals: [],
    currentDeal: null,
    filters: {},
    isLoading: false,
    pagination: {},
    kanbanColumns: [],
    error: null,
  },

  getters: {
    allDeals: (state, _getters, _rootState, rootGetters) =>
      hasCurrentAuthority(state, rootGetters) ? state.deals : [],
    currentDeal: (state, _getters, _rootState, rootGetters) =>
      state.detailScope === authorityScope(rootGetters)
        ? state.currentDeal
        : null,
    detailError: (state, _getters, _rootState, rootGetters) =>
      state.detailScope === authorityScope(rootGetters)
        ? state.detailError
        : null,
    dealById: (_state, getters) => id =>
      getters.allDeals.find(deal => Number(deal.id) === Number(id)),
    dealsByStage: (state, getters, _rootState, rootGetters) =>
      hasCurrentAuthority(state, rootGetters)
        ? state.kanbanColumns.map(stage => ({
            stage,
            deals: getters.allDeals.filter(
              deal => Number(deal.stage_id) === Number(stage.id)
            ),
          }))
        : [],
    openDeals: (_state, getters) =>
      getters.allDeals.filter(deal => deal.status === 'open'),
    overdue: (_state, getters) =>
      getters.allDeals.filter(deal => deal.overdue || deal.is_overdue),
    isLoading: (state, _getters, _rootState, rootGetters) =>
      (hasCurrentAuthority(state, rootGetters) && state.isLoading) ||
      (state.detailScope === authorityScope(rootGetters) &&
        state.detailLoading),
    error: (state, _getters, _rootState, rootGetters) =>
      (hasCurrentAuthority(state, rootGetters) ? state.error : null) ||
      (state.detailScope === authorityScope(rootGetters)
        ? state.detailError
        : null),
  },

  mutations: {
    SET_AUTHORITY_SCOPE(state, scope) {
      state.authorityScope = scope;
    },
    START_DETAIL_REQUEST(state, scope) {
      state.detailScope = scope;
      state.detailRequestId += 1;
      state.currentDeal = null;
      state.detailLoading = false;
      state.detailError = null;
    },
    SET_DETAIL_LOADING(state, value) {
      state.detailLoading = value;
    },
    SET_DETAIL_ERROR(state, value) {
      state.detailError = value;
    },
    SET_LIST_REQUEST_ID(state, value) {
      state.listRequestId = value;
    },
    SET_DEALS(state, payload) {
      state.deals = Array.isArray(payload) ? payload : [];
    },

    SET_CURRENT_DEAL(state, payload) {
      state.currentDeal = payload;

      if (!payload?.id || state.authorityScope !== state.detailScope) return;

      const index = state.deals.findIndex(
        deal => Number(deal.id) === Number(payload.id)
      );

      if (index !== -1) {
        state.deals.splice(index, 1, {
          ...state.deals[index],
          ...payload,
        });
      }
    },

    SET_LOADING(state, payload) {
      state.isLoading = payload;
    },

    SET_ERROR(state, payload) {
      state.error = payload;
    },

    SET_FILTERS(state, payload) {
      state.filters = payload;
    },

    UPDATE_DEAL_STAGE(state, { dealId, stageId }) {
      const deal = state.deals.find(item => Number(item.id) === Number(dealId));

      if (deal) {
        deal.stage_id = stageId;

        if (deal.stage) {
          deal.stage.id = stageId;
        }
      }

      if (
        state.currentDeal &&
        Number(state.currentDeal.id) === Number(dealId)
      ) {
        state.currentDeal.stage_id = stageId;
      }
    },

    ROLLBACK_DEAL_STAGE(state, { dealId, stageId }) {
      const deal = state.deals.find(item => Number(item.id) === Number(dealId));

      if (deal) {
        deal.stage_id = stageId;

        if (deal.stage) {
          deal.stage.id = stageId;
        }
      }

      if (
        state.currentDeal &&
        Number(state.currentDeal.id) === Number(dealId)
      ) {
        state.currentDeal.stage_id = stageId;
      }
    },

    SET_KANBAN_COLUMNS(state, payload) {
      state.kanbanColumns = Array.isArray(payload) ? payload : [];
    },
  },

  actions: {
    async fetchDeals({ commit, state, rootGetters }, params = {}) {
      const requestId = state.listRequestId + 1;
      commit('SET_LIST_REQUEST_ID', requestId);
      const scope = authorityScope(rootGetters);
      commit('SET_AUTHORITY_SCOPE', scope);
      commit('SET_KANBAN_COLUMNS', []);
      commit('SET_DEALS', []);
      commit('SET_LOADING', true);
      commit('SET_ERROR', null);

      try {
        const response = await dealsAPI.list(params);
        if (
          requestId !== state.listRequestId ||
          scope !== authorityScope(rootGetters)
        )
          return;

        const payload = response.data?.payload || response.data;

        commit('SET_DEALS', payload);
      } catch (error) {
        if (
          requestId !== state.listRequestId ||
          scope !== authorityScope(rootGetters)
        )
          return;
        console.error('CRM deals list request failed', {
          status: error.response?.status,
        });

        commit(
          'SET_ERROR',
          error.response?.data?.error ||
            'Não foi possível carregar os negócios.'
        );
      } finally {
        if (
          requestId === state.listRequestId &&
          scope === authorityScope(rootGetters)
        )
          commit('SET_LOADING', false);
      }
    },

    async fetchDeal({ commit, state, rootGetters }, id) {
      const scope = authorityScope(rootGetters);
      commit('START_DETAIL_REQUEST', scope);
      const requestId = state.detailRequestId;
      if (!id) return;
      commit('SET_DETAIL_LOADING', true);
      try {
        const response = await dealsAPI.show(id);
        if (
          requestId !== state.detailRequestId ||
          scope !== authorityScope(rootGetters)
        )
          return;
        const payload = response.data?.payload || response.data;
        commit('SET_CURRENT_DEAL', payload);
      } catch (error) {
        if (
          requestId !== state.detailRequestId ||
          scope !== authorityScope(rootGetters)
        )
          return;
        console.error('CRM deal detail request failed', {
          status: error.response?.status,
        });
        commit(
          'SET_DETAIL_ERROR',
          error.response?.data?.error || 'Não foi possível carregar o negócio.'
        );
      } finally {
        if (
          requestId === state.detailRequestId &&
          scope === authorityScope(rootGetters)
        )
          commit('SET_DETAIL_LOADING', false);
      }
    },

    async moveStage(_, { dealId, stageId, lostReasonId = null }) {
      await dealsAPI.moveStage(dealId, {
        stage_id: stageId,
        lost_reason_id: lostReasonId,
      });
    },

    async fetchKanbanData({ commit, state, rootGetters }, filters = {}) {
      commit('SET_FILTERS', { ...filters });
      commit('SET_LIST_REQUEST_ID', state.listRequestId + 1);
      const request = state.listRequestId;
      const scope = authorityScope(rootGetters);
      commit('SET_AUTHORITY_SCOPE', scope);
      const pipelineId = filters.pipeline_id || filters.pipelineId;
      const pipelines = rootGetters['jrcCrm/pipelines/allPipelines'];
      const pipelineIds = pipelineId ? [pipelineId] : pipelines.map(p => p.id);
      commit('SET_LOADING', true);
      commit('SET_ERROR', null);
      commit('SET_KANBAN_COLUMNS', []);
      commit('SET_DEALS', []);
      try {
        const [stagesResponses, dealsResponse] = await Promise.all([
          Promise.all(
            pipelineIds.map(id => stagesAPI.list({ pipeline_id: id }))
          ),
          dealsAPI.list({
            pipeline_id: pipelineId || undefined,
            owner_id: filters.owner_id || undefined,
            search: filters.search,
          }),
        ]);
        if (
          request !== state.listRequestId ||
          scope !== authorityScope(rootGetters)
        )
          return;
        const stages = stagesResponses.flatMap(
          response => response.data?.payload || response.data
        );
        const deals = dealsResponse.data?.payload || dealsResponse.data;
        if (!Array.isArray(deals) || stages.some(stage => !stage?.id)) {
          throw new Error('Invalid funnel response');
        }
        commit('SET_KANBAN_COLUMNS', stages);
        commit(
          'SET_DEALS',
          deals.filter(
            deal =>
              (!filters.overdueOnly ||
                deal.overdue ||
                deal.next_activity?.is_overdue) &&
              (!filters.noNextActivity || !deal.next_activity)
          )
        );
      } catch (error) {
        if (
          request !== state.listRequestId ||
          scope !== authorityScope(rootGetters)
        )
          return;
        commit(
          'SET_ERROR',
          error.response?.data?.error || 'Não foi possível carregar o funil.'
        );
      } finally {
        if (
          request === state.listRequestId &&
          scope === authorityScope(rootGetters)
        )
          commit('SET_LOADING', false);
      }
    },
  },
};
