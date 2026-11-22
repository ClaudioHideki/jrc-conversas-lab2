import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import API from 'dashboard/api/jrcContactCenter';

const calendar = '11111111-1111-4111-8111-111111111111';
const revision = 'a'.repeat(64);
const axios = { get: vi.fn(), post: vi.fn(), patch: vi.fn(), delete: vi.fn() };
beforeEach(() => {
  vi.clearAllMocks();
  vi.stubGlobal('axios', axios);
});
afterEach(() => vi.unstubAllGlobals());

describe('calendar API wire identity, not server authorization or persistence proof', () => {
  it('keeps the native account route and explicit unit authoritative over filter overrides', () => {
    API.unitCalendars('1', '10', {
      unit_id: '999',
      q: 'SYNTHETIC',
      page: 2,
      per_page: 20,
    });
    expect(axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/unit_calendars',
      {
        params: { unit_id: '10', q: 'SYNTHETIC', page: 2, per_page: 20 },
      }
    );
  });

  it('uses only the native create, update, details and preview contracts with explicit unit and revision', () => {
    const entry = {
      id: calendar,
      active: false,
      definition: { name: 'SYNTHETIC wire test' },
    };
    API.saveUnitCalendar('1', '10', entry, revision);
    expect(axios.post).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/unit_calendars',
      {
        unit_id: '10',
        calendar: entry,
        expected_revision: revision,
      }
    );
    API.saveUnitCalendar('1', '10', entry, revision, true);
    expect(axios.patch).toHaveBeenCalledWith(
      `/api/v1/accounts/1/jrc_contact_center/unit_calendars/${calendar}`,
      {
        unit_id: '10',
        calendar: entry,
        expected_revision: revision,
      }
    );
    API.unitCalendar('1', '10', calendar);
    expect(axios.get).toHaveBeenCalledWith(
      `/api/v1/accounts/1/jrc_contact_center/unit_calendars/${calendar}`,
      { params: { unit_id: '10' } }
    );
    API.previewUnitCalendar('1', '10', calendar, '2026-11-23');
    expect(axios.get).toHaveBeenCalledWith(
      `/api/v1/accounts/1/jrc_contact_center/unit_calendars/${calendar}/preview`,
      {
        params: { unit_id: '10', date: '2026-11-23' },
      }
    );
  });

  it.each([
    '',
    '../other',
    '11111111-1111-1111-8111-111111111111',
    '11111111-1111-4111-7111-111111111111',
  ])('rejects malformed calendar identity %s before any request', id => {
    expect(() => API.unitCalendar('1', '10', id)).toThrow(
      'Invalid local calendar identity'
    );
    expect(axios.get).not.toHaveBeenCalled();
  });

  it.each(['10invalid', '0', '9223372036854775808'])(
    'rejects malformed unit identity %s before any request',
    unit => {
      expect(() => API.unitCalendars('1', unit)).toThrow(
        'Invalid local record identity'
      );
      expect(axios.get).not.toHaveBeenCalled();
    }
  );

  it('preserves an exact native bigint string without numeric truncation', () => {
    API.unitCalendars('1', '9007199254740993');
    expect(axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/unit_calendars',
      { params: { unit_id: '9007199254740993' } }
    );
  });

  it('keeps explicit account, unit and calendar identities authoritative in the paginated queue binding inventory', () => {
    API.queueCalendars('1', '10', calendar, {
      unit_id: '999',
      calendar_id: 'other',
      q: 'SYNTHETIC',
      page: 2,
    });
    expect(axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/queue_calendars',
      {
        params: {
          unit_id: '10',
          calendar_id: calendar,
          q: 'SYNTHETIC',
          page: 2,
        },
      }
    );
  });

  it('reads current queue state and sends the exact reviewed idempotent body through only the typed native route', () => {
    API.queueCalendar('1', '10', '20');
    expect(axios.get).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/queue_calendars/20',
      { params: { unit_id: '10' } }
    );
    const body = Object.freeze({
      unit_id: '10',
      queue_id: '20',
      reviewed: true,
      calendar_id: calendar,
    });
    API.saveQueueCalendar('1', '20', body);
    expect(axios.patch).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/queue_calendars/20',
      body
    );
    expect(axios.patch.mock.calls[0][1]).toBe(body);
  });

  it('rejects malformed queue routes and calendar identities before the transport can be invoked', () => {
    expect(() => API.queueCalendar('1', '10', '../other')).toThrow(
      'Invalid local record identity'
    );
    expect(() => API.queueCalendars('1', '10', '../other')).toThrow(
      'Invalid local calendar identity'
    );
    expect(axios.get).not.toHaveBeenCalled();
  });
});

describe('reviewed internal removal API wire, not server authority proof', () => {
  it('sends the exact reviewed body through the typed DELETE contract without URL payload or generic queue writes', () => {
    const body = Object.freeze({
      unit_id: '10',
      queue_id: '20',
      binding_id: calendar,
      expected_revision: revision,
      idempotency_key: '22222222-2222-4222-8222-222222222222',
      reviewed: true,
    });
    API.removeQueueCalendar('1', '20', body);
    expect(axios.delete).toHaveBeenCalledWith(
      '/api/v1/accounts/1/jrc_contact_center/queue_calendars/20',
      { data: body }
    );
    expect(axios.delete.mock.calls[0][1].data).toBe(body);
    expect(axios.patch).not.toHaveBeenCalled();
  });
  it.each(['0', '../other', '9223372036854775808'])(
    'rejects malformed queue identity %s before requesting removal',
    queueId => {
      expect(() => API.removeQueueCalendar('1', queueId, {})).toThrow(
        'Invalid local record identity'
      );
      expect(axios.delete).not.toHaveBeenCalled();
    }
  );
});
