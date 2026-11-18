import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import API from 'dashboard/api/jrcContactCenter';

let http;
beforeEach(() => {
  http = { get: vi.fn(), post: vi.fn(), patch: vi.fn() };
  vi.stubGlobal('axios', http);
});
afterEach(() => {
  vi.unstubAllGlobals();
});

describe('native local IVR API identities', () => {
  it('keeps authorized bigint reference strings exact rather than rounding them in JavaScript', () => {
    API.ivrReference('1', 'units', '9007199254740993');
    expect(http.get).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/units/9007199254740993'
    );
    API.configurationRecord('1', 'ivr_drafts', '9007199254740993');
    expect(http.get).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/ivr_drafts/9007199254740993'
    );
  });
  it('rejects unsafe numeric, foreign-route and oversized record identities before a request is sent', () => {
    expect(() =>
      API.ivrReference('1', 'units', Number.MAX_SAFE_INTEGER + 1)
    ).toThrow();
    expect(() =>
      API.ivrReference('1', 'units', '9999999999999999999')
    ).toThrow();
    expect(() => API.ivrReference('1', 'commands', '1')).toThrow();
    expect(() => API.ivrReference('1', 'units', '1\n')).toThrow();
    expect(() => API.ivrReference('1\n', 'units', '1')).toThrow();
    expect(() => API.configurationRecord('1', 'ivr_drafts', '../2')).toThrow();
    expect(http.get).not.toHaveBeenCalled();
  });
  it('uses only the native account endpoints and named private payloads', () => {
    API.previewIvrDraft('1', { unit_id: '7', dtmf: '' });
    expect(http.post).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/ivr_drafts/preview',
      { ivr_preview: { unit_id: '7', dtmf: '' } }
    );
    API.simulateIvrDraft('1', '10', 2, '1#');
    expect(http.post).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/ivr_drafts/10/simulate',
      { ivr_simulation: { revision: 2, dtmf: '1#' } }
    );
  });
  it('does not turn arbitrary version strings into an accepted revision', () => {
    expect(() => API.ivrVersion('1', '10', '2')).toThrow();
    expect(() => API.exportIvrDraft('1', '10', 0)).toThrow();
    expect(http.get).not.toHaveBeenCalled();
  });
});
