import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import API from 'dashboard/api/jrcContactCenter';

let http;
beforeEach(() => {
  http = { get: vi.fn(), patch: vi.fn() };
  vi.stubGlobal('axios', http);
});
afterEach(() => vi.unstubAllGlobals());

describe('native team supervision transport', () => {
  it('preserves exact bigint team IDs in metadata and paginated candidate reads', () => {
    API.configurationRecord('1', 'team_supervisions', '9007199254740993');
    expect(http.get).toHaveBeenLastCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/team_supervisions/9007199254740993'
    );
    API.teamSupervisionCandidates('1', '9007199254740993', {
      page: 2,
      per_page: 20,
      q: 'SYNTHETIC',
    });
    expect(http.get).toHaveBeenLastCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/team_supervisions/9007199254740993/candidates',
      { params: { page: 2, per_page: 20, q: 'SYNTHETIC' } }
    );
  });

  it('sends the reviewed selection and revision without copying grants or manager confirmations into metadata', () => {
    const selection = {
      primary_account_user_id: '9007199254740993',
      additional_account_user_ids: ['7'],
    };
    API.saveTeamSupervision('1', '4', selection, {
      expected_revision: 'a'.repeat(64),
      allowed: ['jrc_contact_center_quality_review'],
    });
    expect(http.patch).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/team_supervisions/4',
      { supervision: selection, expected_revision: 'a'.repeat(64) }
    );
  });

  it.each(['../commands', '4\n', Number.MAX_SAFE_INTEGER + 1])(
    'refuses unsafe team identity %s before any transport',
    id => {
      expect(() => API.teamSupervisionCandidates('1', id)).toThrow();
      expect(() => API.saveTeamSupervision('1', id, {}, {})).toThrow();
      expect(http.get).not.toHaveBeenCalled();
      expect(http.patch).not.toHaveBeenCalled();
    }
  );
});
