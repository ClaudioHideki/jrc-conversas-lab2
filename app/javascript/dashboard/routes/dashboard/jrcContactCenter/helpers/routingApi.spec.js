import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import API from 'dashboard/api/jrcContactCenter';

let http;
beforeEach(() => {
  http = { get: vi.fn(), post: vi.fn(), patch: vi.fn() };
  vi.stubGlobal('axios', http);
});

describe('native qualification manual-state API', () => {
  it('uses the existing account route and preserves the exact native bigint identity and draft revision', () => {
    API.saveQualificationDraft(
      '1',
      '9007199254740993',
      { notes: 'SYNTHETIC pending' },
      'revision-a'
    );
    expect(http.patch).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/qualifications/9007199254740993/draft',
      {
        qualification: { notes: 'SYNTHETIC pending' },
        expected_draft_revision: 'revision-a',
      }
    );
  });
  it('preserves legacy completion and sends the optional revision only for callers that supply it', () => {
    API.completeQualification('1', 11, {
      reason_code: 'order',
      outcome_code: 'completed',
    });
    expect(http.patch).toHaveBeenLastCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/qualifications/11',
      {
        qualification: { reason_code: 'order', outcome_code: 'completed' },
      }
    );
    API.completeQualification(
      '1',
      11,
      { reason_code: 'order', outcome_code: 'completed' },
      { expected_draft_revision: 'revision-a' }
    );
    expect(http.patch).toHaveBeenLastCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/qualifications/11',
      {
        qualification: { reason_code: 'order', outcome_code: 'completed' },
        expected_draft_revision: 'revision-a',
      }
    );
  });
  it.each(['../commands', '1\n', Number.MAX_SAFE_INTEGER + 1])(
    'rejects unsafe draft or completion identity %s',
    id => {
      expect(() =>
        API.saveQualificationDraft('1', id, {}, 'revision-a')
      ).toThrow();
      expect(() => API.completeQualification('1', id, {})).toThrow();
      expect(http.patch).not.toHaveBeenCalled();
    }
  );
});
afterEach(() => vi.unstubAllGlobals());

describe('existing native routing API', () => {
  it('preserves pagination parameters and exact bigint record identities', () => {
    API.routingRules('1', { page: 2, per_page: 20, q: 'SYNTHETIC' });
    expect(http.get).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/routing_rules',
      { params: { page: 2, per_page: 20, q: 'SYNTHETIC' } }
    );
    API.configurationRecord('1', 'routing_rules', '9007199254740993');
    expect(http.get).toHaveBeenLastCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/routing_rules/9007199254740993'
    );
  });
  it('submits the native revision and rejects unsafe or injected record identities', () => {
    API.saveRoutingRule('1', { priority: 2 }, '9007199254740993', {
      expected_revision: 'a'.repeat(64),
    });
    expect(http.patch).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/routing_rules/9007199254740993',
      { routing_rule: { priority: 2 }, expected_revision: 'a'.repeat(64) }
    );
    expect(() =>
      API.saveRoutingRule('1', {}, Number.MAX_SAFE_INTEGER + 1)
    ).toThrow();
    expect(() => API.saveRoutingRule('1', {}, '../commands')).toThrow();
    expect(() =>
      API.configurationRecord('1', 'routing_rules', '1\n')
    ).toThrow();
    expect(http.patch).toHaveBeenCalledTimes(1);
  });
});
