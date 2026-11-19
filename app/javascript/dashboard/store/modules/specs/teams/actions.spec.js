import axios from 'axios';
import { actions } from '../../teams/actions';
import {
  SET_TEAM_UI_FLAG,
  CLEAR_TEAMS,
  SET_TEAMS,
  SET_TEAM_ITEM,
  EDIT_TEAM,
  DELETE_TEAM,
} from '../../teams/types';
import teamsList from './fixtures';

const commit = vi.fn();
global.axios = axios;
vi.mock('axios');

describe('#actions', () => {
  describe('#get', () => {
    it('sends correct actions if API is success', async () => {
      const mockedGet = vi.fn(url => {
        if (url === '/api/v1/teams') {
          return Promise.resolve({ data: teamsList[1] });
        }
        if (url === '/api/v1/accounts//cache_keys') {
          return Promise.resolve({ data: { cache_keys: { teams: 0 } } });
        }
        // Return default value or throw an error for unexpected requests
        return Promise.reject(new Error('Unexpected request: ' + url));
      });

      axios.get = mockedGet;

      await actions.get({ commit });
      expect(commit.mock.calls).toEqual([
        [SET_TEAM_UI_FLAG, { isFetching: true }],
        [CLEAR_TEAMS],
        [SET_TEAMS, teamsList[1]],
        [SET_TEAM_UI_FLAG, { isFetching: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.get.mockRejectedValue({ message: 'Incorrect header' });
      await expect(actions.get({ commit })).rejects.toThrow(Error);
      expect(commit.mock.calls).toEqual([
        [SET_TEAM_UI_FLAG, { isFetching: true }],
        [SET_TEAM_UI_FLAG, { isFetching: false }],
      ]);
    });
  });

  describe('#create', () => {
    it('sends correct actions if API is success', async () => {
      axios.post.mockResolvedValue({ data: teamsList[1] });
      await actions.create({ commit }, teamsList[1]);

      expect(commit.mock.calls).toEqual([
        [SET_TEAM_UI_FLAG, { isCreating: true }],
        [SET_TEAM_ITEM, teamsList[1]],
        [SET_TEAM_UI_FLAG, { isCreating: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.post.mockRejectedValue({ message: 'Incorrect header' });
      await expect(actions.create({ commit })).rejects.toThrow(Error);

      expect(commit.mock.calls).toEqual([
        [SET_TEAM_UI_FLAG, { isCreating: true }],
        [SET_TEAM_UI_FLAG, { isCreating: false }],
      ]);
    });
  });

  describe('#update', () => {
    it('sends correct actions if API is success', async () => {
      axios.patch.mockResolvedValue({ data: teamsList[1] });
      await actions.update({ commit }, teamsList[1]);

      expect(commit.mock.calls).toEqual([
        [SET_TEAM_UI_FLAG, { isUpdating: true }],
        [EDIT_TEAM, teamsList[1]],
        [SET_TEAM_UI_FLAG, { isUpdating: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.patch.mockRejectedValue({ message: 'Incorrect header' });
      await expect(actions.update({ commit }, teamsList[1])).rejects.toThrow(
        Error
      );
      expect(commit.mock.calls).toEqual([
        [SET_TEAM_UI_FLAG, { isUpdating: true }],
        [SET_TEAM_UI_FLAG, { isUpdating: false }],
      ]);
    });
  });

  describe('#delete', () => {
    it('preserves the exact native review error and does not remove the team before manager confirmation', async () => {
      const error = {
        response: {
          status: 409,
          data: { error: 'team_deletion_confirmation_required' },
        },
      };
      axios.delete.mockRejectedValue(error);
      await expect(
        actions.delete({ commit }, { id: 2, accountId: '3' })
      ).rejects.toBe(error);
      expect(commit).not.toHaveBeenCalledWith(DELETE_TEAM, 2);
    });

    it('does not commit an old-account deletion into the current-account team list', async () => {
      axios.delete.mockResolvedValue();
      await actions.delete({ commit }, { id: 2, accountId: '3' });
      expect(axios.delete).toHaveBeenCalledWith('/api/v1/accounts/3/teams/2', {
        data: {},
      });
      expect(commit).not.toHaveBeenCalledWith(DELETE_TEAM, 2);
    });

    it('sends correct actions if API is success', async () => {
      axios.delete.mockResolvedValue();
      await actions.delete({ commit }, 1);
      expect(commit.mock.calls).toEqual([
        [SET_TEAM_UI_FLAG, { isDeleting: true }],
        [DELETE_TEAM, 1],
        [SET_TEAM_UI_FLAG, { isDeleting: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.delete.mockRejectedValue({ message: 'Incorrect header' });
      await expect(actions.delete({ commit }, 1)).rejects.toThrow(Error);
      expect(commit.mock.calls).toEqual([
        [SET_TEAM_UI_FLAG, { isDeleting: true }],
        [SET_TEAM_UI_FLAG, { isDeleting: false }],
      ]);
    });
  });
});
