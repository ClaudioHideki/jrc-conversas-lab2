import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import API from 'dashboard/api/jrcContactCenter';

let http;
beforeEach(() => {
  http = { patch: vi.fn() };
  vi.stubGlobal('axios', http);
});
afterEach(() => vi.unstubAllGlobals());

describe('native team source update transport', () => {
  it('binds the manager receipt to the native server key and preserves the exact bigint identity', () => {
    const receipt = {
      confirmed: true,
      review_token: 'synthetic-server-receipt',
    };
    API.saveAccessAuthorization(
      '1',
      'teams',
      '9007199254740993',
      { active: false, allowed: [] },
      {
        expected_revision: 'synthetic-source-revision',
        managerConfirmation: receipt,
      }
    );
    expect(http.patch).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/access_authorizations/teams/9007199254740993',
      {
        authorization: { active: false, allowed: [] },
        expected_revision: 'synthetic-source-revision',
        manager_confirmation: receipt,
      }
    );
    expect(http.patch.mock.calls[0][1]).not.toHaveProperty(
      'managerConfirmation'
    );
  });

  it('preserves the ordinary individual grant contract without inventing a manager confirmation', () => {
    API.saveAccessAuthorization(
      '1',
      'users',
      '3',
      { eligible: true },
      { expected_revision: 'synthetic-revision' }
    );
    expect(http.patch).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/access_authorizations/users/3',
      {
        authorization: { eligible: true },
        expected_revision: 'synthetic-revision',
      }
    );
  });

  it.each(['../commands', '1\n', Number.MAX_SAFE_INTEGER + 1])(
    'refuses unsafe identity %s before network access',
    id => {
      expect(() =>
        API.saveAccessAuthorization('1', 'teams', id, { active: false }, {})
      ).toThrow();
      expect(http.patch).not.toHaveBeenCalled();
    }
  );
});
