import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import API from 'dashboard/api/jrcContactCenter';

let http;
beforeEach(() => {
  http = { get: vi.fn(), post: vi.fn(), patch: vi.fn() };
  vi.stubGlobal('axios', http);
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
