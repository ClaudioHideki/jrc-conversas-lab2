import {
  SET_TEAM_UI_FLAG,
  CLEAR_TEAMS,
  SET_TEAMS,
  SET_TEAM_ITEM,
  EDIT_TEAM,
  DELETE_TEAM,
} from './types';
import TeamsAPI from '../../../api/teams';

export const actions = {
  create: async ({ commit }, teamInfo) => {
    commit(SET_TEAM_UI_FLAG, { isCreating: true });
    try {
      const response = await TeamsAPI.create(teamInfo);
      const team = response.data;
      commit(SET_TEAM_ITEM, team);
      return team;
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(SET_TEAM_UI_FLAG, { isCreating: false });
    }
  },
  revalidate: async ({ commit }, { newKey }) => {
    try {
      const isExistingKeyValid = await TeamsAPI.validateCacheKey(newKey);
      if (!isExistingKeyValid) {
        const response = await TeamsAPI.refetchAndCommit(newKey);
        commit(SET_TEAMS, response.data);
      }
    } catch (error) {
      // Ignore error
    }
  },
  get: async ({ commit }) => {
    commit(SET_TEAM_UI_FLAG, { isFetching: true });
    try {
      const { data } = await TeamsAPI.get(true);
      commit(CLEAR_TEAMS);
      commit(SET_TEAMS, data);
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(SET_TEAM_UI_FLAG, { isFetching: false });
    }
  },

  show: async ({ commit }, { id }) => {
    commit(SET_TEAM_UI_FLAG, { isFetchingItem: true });
    try {
      const response = await TeamsAPI.show(id);
      commit(SET_TEAM_ITEM, response.data.payload);
      commit(SET_TEAM_UI_FLAG, {
        isFetchingItem: false,
      });
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(SET_TEAM_UI_FLAG, {
        isFetchingItem: false,
      });
    }
  },

  update: async ({ commit }, { id, ...updateObj }) => {
    commit(SET_TEAM_UI_FLAG, { isUpdating: true });
    try {
      const response = await TeamsAPI.update(id, updateObj);
      commit(EDIT_TEAM, response.data);
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(SET_TEAM_UI_FLAG, { isUpdating: false });
    }
  },

  delete: async ({ commit }, teamId) => {
    commit(SET_TEAM_UI_FLAG, { isDeleting: true });
    try {
      const reviewed = typeof teamId === 'object' && teamId !== null;
      if (reviewed) {
        await TeamsAPI.deleteWithReview(teamId);
        if (String(TeamsAPI.accountIdFromRoute) !== String(teamId.accountId))
          return;
      } else await TeamsAPI.delete(teamId);
      commit(DELETE_TEAM, reviewed ? teamId.id : teamId);
    } catch (error) {
      if (typeof teamId === 'object' && teamId !== null) throw error;
      throw new Error(error);
    } finally {
      commit(SET_TEAM_UI_FLAG, { isDeleting: false });
    }
  },
};
