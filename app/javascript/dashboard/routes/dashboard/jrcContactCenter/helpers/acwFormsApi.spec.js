import { beforeEach, describe, expect, it, vi } from 'vitest';
import API from 'dashboard/api/jrcContactCenter';
beforeEach(() => {
  global.axios = { get: vi.fn(), post: vi.fn(), patch: vi.fn() };
});
describe('ACW form library native API paths', () => {
  it('pins a bigint form ID and revision without lossy numeric coercion', () => {
    API.acwFormVersion('1', '9223372036854775807', 2147483647);
    expect(global.axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/acw_forms/9223372036854775807/versions/2147483647'
    );
  });
  it('shares the existing configuration read path and preserves the native request envelope', () => {
    API.configurationRecord(1, 'acw_forms', '19');
    expect(global.axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/acw_forms/19'
    );
    const form = {
      name: 'SYNTHETIC form',
      request_id: 'SYNTHETIC same request',
    };
    API.saveAcwForm(1, '19', form);
    expect(global.axios.patch).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/acw_forms/19',
      { acw_form: form }
    );
  });
  it.each(['1/../../other', '0', '9223372036854775808', '19\n'])(
    'rejects an unsafe record identity %s without any HTTP call',
    id => {
      expect(() => API.saveAcwForm(1, id, {})).toThrow();
      expect(global.axios.patch).not.toHaveBeenCalled();
    }
  );
  it.each([0, '1', 2147483648, 1.5])(
    'rejects an invalid exact version %s without a request',
    revision => {
      expect(() => API.acwFormVersion(1, '19', revision)).toThrow();
      expect(global.axios.get).not.toHaveBeenCalled();
    }
  );
});

describe('Owned operational ACW form read uses the actual shared API', () => {
  it('preserves the exact attendance identity and reason in a read-only request', () => {
    API.qualificationFormContext('1', '9223372036854775807', 'order');
    expect(global.axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/qualifications/9223372036854775807/form_context',
      { params: { reason_code: 'order' } }
    );
    expect(global.axios.post).not.toHaveBeenCalled();
    expect(global.axios.patch).not.toHaveBeenCalled();
  });
  it.each(['1/../../other', '0', '9223372036854775808', '19\n'])(
    'rejects unsafe operational attendance identity %s before HTTP',
    id => {
      expect(() => API.qualificationFormContext(1, id, 'order')).toThrow();
      expect(global.axios.get).not.toHaveBeenCalled();
    }
  );
});
