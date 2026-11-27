import { describe, expect, it } from 'vitest';
import {
  decodeRecordingTicketSource,
  selectedRecordingForTicket,
} from './recordingTicketSource';

const source = () => ({
  contract_version: 1,
  account_id: '1',
  user_id: '7',
  recording_id: '8',
  call_session_id: '9',
  call_id: 'SYNTHETIC real linked call',
  contact_id: '33',
  service_desk_unit_id: '10',
});
const payload = () => ({ unit_id: '10', ticket: { requester_id: '33' } });

describe('native recording origin bound to the existing Ticket submission', () => {
  it('accepts the exact current context and returns only the recording selector', () => {
    const value = decodeRecordingTicketSource(source(), '1', '7', '8');
    expect(Object.isFrozen(value)).toBe(true);
    expect(selectedRecordingForTicket(value, '1', '7', payload())).toBe('8');
  });
  it.each(['account_id', 'user_id', 'recording_id'])(
    'rejects another %s returned by the server',
    field => {
      expect(() =>
        decodeRecordingTicketSource(
          { ...source(), [field]: '999' },
          '1',
          '7',
          '8'
        )
      ).toThrow(TypeError);
    }
  );
  it.each(['unit_id', 'requester_id'])(
    'does not authorize a destination override: %s',
    field => {
      const value = payload();
      if (field === 'unit_id') value.unit_id = '999';
      else value.ticket.requester_id = '999';
      expect(() =>
        selectedRecordingForTicket(source(), '1', '7', value)
      ).toThrow(TypeError);
    }
  );
  it.each([undefined, null, false, ['8'], { id: '8' }, '8suffix'])(
    'rejects malformed origin data without ordinary intake fallback: %s',
    recording => {
      expect(() =>
        decodeRecordingTicketSource(
          { ...source(), recording_id: recording },
          '1',
          '7',
          '8'
        )
      ).toThrow(TypeError);
    }
  );
  it('rejects an absent preview, wrong contract and untrusted call text', () => {
    expect(() => selectedRecordingForTicket(null, '1', '7', payload())).toThrow(
      TypeError
    );
    expect(() =>
      decodeRecordingTicketSource(
        { ...source(), contract_version: 2 },
        '1',
        '7',
        '8'
      )
    ).toThrow(TypeError);
    expect(() =>
      decodeRecordingTicketSource(
        { ...source(), call_id: 'untrusted\ncall' },
        '1',
        '7',
        '8'
      )
    ).toThrow(TypeError);
  });
});
