/* eslint-disable no-console */

import { dealsAPI, stagesAPI } from '../../../api/crm';

export default {
  namespaced: true,

  state: {
    deals: [],
    currentDeal: null,
    filters: {},
    isLoading: false,
    pagination: {},
    kanbanColumns: [],
    error: null,
    kanbanRequest: 0,
  },

  getters: {
    allDeals: state => state.deals,
    currentDeal: state => state.currentDeal,

    dealById: state => id =>
      state.deals.find(deal => Number(deal.id) === Number(id)),

    dealsByStage: state => {
      return state.kanbanColumns.map(col => ({
        stage: col,
        deals: state.deals.filter(
          deal => Number(deal.stage_id) === Number(col.id)
        ),
      }));
    },

    openDeals: state => state.deals.filter(deal => deal.status === 'open'),

    overdue: state =>
      state.deals.filter(deal => deal.overdue || deal.is_overdue),

    isLoading: state => state.isLoading,
    error: state => state.error,
  },

  mutations: {
    SET_DEALS(state, payload) {
      state.deals = Array.isArray(payload) ? payload : [];
    },

    SET_CURRENT_DEAL(state, payload) {
      state.currentDeal = payload;

      if (!payload?.id) return;

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
    START_KANBAN_REQUEST(state) {
      state.kanbanRequest += 1;
    },
  },

  actions: {
    async fetchDeals({ commit }, params = {}) {
      commit('SET_LOADING', true);
      commit('SET_ERROR', null);

      try {
        const response = await dealsAPI.list(params);

        const payload = response.data?.payload || response.data;

        console.log(
          'JRC CRM DEALS API COMPLETO:',
          JSON.stringify(payload, null, 2)
        );

        commit('SET_DEALS', payload);
      } catch (error) {
        console.error('Erro ao carregar negócios:', error);

        commit(
          'SET_ERROR',
          error.response?.data?.error ||
            'Não foi possível carregar os negócios.'
        );
      } finally {
        commit('SET_LOADING', false);
      }
    },

    async fetchDeal({ commit }, id) {
      if (!id) {
        commit('SET_CURRENT_DEAL', null);
        return;
      }

      commit('SET_LOADING', true);
      commit('SET_ERROR', null);

      try {
        const response = await dealsAPI.show(id);

        const payload = response.data?.payload || response.data;

        console.log(
          'JRC CRM DEAL INDIVIDUAL:',
          JSON.stringify(payload, null, 2)
        );

        commit('SET_CURRENT_DEAL', payload);
      } catch (error) {
        console.error('Erro ao carregar negócio:', error);

        commit(
          'SET_ERROR',
          error.response?.data?.error || 'Não foi possível carregar o negócio.'
        );
      } finally {
        commit('SET_LOADING', false);
      }
    },

    async moveStage(_, { dealId, stageId, lostReasonId = null }) {
      await dealsAPI.moveStage(dealId, {
        stage_id: stageId,
        lost_reason_id: lostReasonId,
      });
    },

    async fetchKanbanData({ commit, state, rootState }, filters = {}) {
      commit('SET_FILTERS', { ...filters });
      commit('START_KANBAN_REQUEST');
      const request = state.kanbanRequest;
      const pipelineId = filters.pipeline_id || filters.pipelineId;
      const pipelines = rootState.jrcCrm.pipelines.pipelines;
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
        if (request !== state.kanbanRequest) return;
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
        if (request !== state.kanbanRequest) return;
        commit(
          'SET_ERROR',
          error.response?.data?.error || 'Não foi possível carregar o funil.'
        );
      } finally {
        if (request === state.kanbanRequest) commit('SET_LOADING', false);
      }
    },
  },
};
