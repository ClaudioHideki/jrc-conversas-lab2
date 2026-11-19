import axios from 'axios';
import {
  actions,
  SET_TEAM_MEMBERS_UI_FLAG,
  ADD_AGENTS_TO_TEAM,
} from '../../teamMembers';
import teamMembers from './fixtures';

const commit = vi.fn();
global.axios = axios;
vi.mock('axios');

describe('#actions', () => {
  describe('#get', () => {
    it('sends correct actions if API is success', async () => {
      axios.get.mockResolvedValue({ data: teamMembers[1] });
      await actions.get({ commit }, { teamId: 1 });
      expect(commit.mock.calls).toEqual([
        [SET_TEAM_MEMBERS_UI_FLAG, { isFetching: true }],
        [ADD_AGENTS_TO_TEAM, { data: teamMembers[1], teamId: 1 }],
        [SET_TEAM_MEMBERS_UI_FLAG, { isFetching: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.get.mockRejectedValue({ message: 'Incorrect header' });
      await expect(actions.get({ commit }, { teamId: 1 })).rejects.toThrow(
        Error
      );
      expect(commit.mock.calls).toEqual([
        [SET_TEAM_MEMBERS_UI_FLAG, { isFetching: true }],
        [SET_TEAM_MEMBERS_UI_FLAG, { isFetching: false }],
      ]);
    });
  });

  describe('#create', () => {
    it('sends correct actions if API is success', async () => {
      axios.post.mockResolvedValue({ data: teamMembers });
      await actions.create({ commit }, { agentsList: teamMembers, teamId: 1 });

      expect(commit.mock.calls).toEqual([
        [SET_TEAM_MEMBERS_UI_FLAG, { isCreating: true }],
        [ADD_AGENTS_TO_TEAM, { data: teamMembers, teamId: 1 }],
        [SET_TEAM_MEMBERS_UI_FLAG, { isCreating: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.post.mockRejectedValue({ message: 'Incorrect header' });
      await expect(
        actions.create({ commit }, { agentsList: teamMembers, teamId: 1 })
      ).rejects.toThrow(Error);

      expect(commit.mock.calls).toEqual([
        [SET_TEAM_MEMBERS_UI_FLAG, { isCreating: true }],
        [SET_TEAM_MEMBERS_UI_FLAG, { isCreating: false }],
      ]);
    });
  });

  describe('#update', () => {
    it('sends correct actions if API is success', async () => {
      axios.patch.mockResolvedValue({ data: teamMembers });
      await actions.update({ commit }, { agentsList: teamMembers, teamId: 1 });

      expect(commit.mock.calls).toEqual([
        [SET_TEAM_MEMBERS_UI_FLAG, { isUpdating: true }],
        [ADD_AGENTS_TO_TEAM, { data: teamMembers, teamId: 1 }],
        [SET_TEAM_MEMBERS_UI_FLAG, { isUpdating: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      const error = {
        message: 'Incorrect header',
        response: {
          status: 409,
          data: { error: 'team_roster_confirmation_required' },
        },
      };
      axios.patch.mockRejectedValue(error);
      await expect(
        actions.update({ commit }, { agentsList: teamMembers, teamId: 1 })
      ).rejects.toBe(error);
      expect(commit.mock.calls).toEqual([
        [SET_TEAM_MEMBERS_UI_FLAG, { isUpdating: true }],
        [SET_TEAM_MEMBERS_UI_FLAG, { isUpdating: false }],
      ]);
    });

    it('preserves an explicitly confirmed receipt and the native team identity on retry', async () => {
      const managerConfirmation = {
        confirmed: true,
        review_token: 'SYNTHETIC receipt',
      };
      axios.patch.mockResolvedValue({ data: teamMembers });
      await actions.update(
        { commit },
        { agentsList: [1], teamId: 2, managerConfirmation }
      );
      expect(axios.patch).toHaveBeenCalledWith('/api/v1/teams/2/team_members', {
        user_ids: [1],
        manager_confirmation: managerConfirmation,
      });
      expect(commit).toHaveBeenCalledWith(ADD_AGENTS_TO_TEAM, {
        data: teamMembers,
        teamId: 2,
      });
    });
  });
});
