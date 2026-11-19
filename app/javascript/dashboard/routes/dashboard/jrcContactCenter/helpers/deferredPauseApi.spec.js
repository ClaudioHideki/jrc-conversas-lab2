import { beforeEach, describe, expect, it, vi } from 'vitest';
import API from 'dashboard/api/jrcContactCenter';

beforeEach(() => {
  global.axios = { post: vi.fn(), delete: vi.fn() };
});

describe('deferred pause self-service native API paths', () => {
  it('preserves the reviewed UUID, revisions and body without deriving another actor', () => {
    const values = {
      command_id: '00000000-0000-4000-8000-000000000019',
      expected_state_version: '9223372036854775807',
      expected_request_revision: 'a'.repeat(64),
      reason_code: 'SYNTHETIC break',
      queue_id: '9223372036854775806',
      justification: 'SYNTHETIC private review',
    };
    API.requestDeferredPause('1', values);
    expect(global.axios.post).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/deferred_pause_request',
      { deferred_pause_request: values }
    );
    expect(global.axios.delete).not.toHaveBeenCalled();
  });

  it('cancels only the selected UUID using the native DELETE body', () => {
    const id = '00000000-0000-4000-8000-000000000019';
    API.cancelDeferredPause('1', id);
    expect(global.axios.delete).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/deferred_pause_request',
      { data: { request_id: id } }
    );
    expect(global.axios.post).not.toHaveBeenCalled();
  });
});
