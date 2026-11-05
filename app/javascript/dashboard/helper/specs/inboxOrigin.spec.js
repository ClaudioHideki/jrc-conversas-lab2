import { describe, expect, it } from 'vitest';
import {
  conversationMessageTimestamp,
  inboxOrigin,
  messageClock,
} from '../inboxOrigin';

describe('source inbox presentation', () => {
  it('never uses a customer phone, an assignee, or an arbitrary provider configuration as the sending identity', () => {
    const result = inboxOrigin({
      id: 11,
      name: 'Lucas',
      channel_type: 'Channel::Api',
      jrc_broker_bound: true,
      provider_config: { phone_number: '+15550000099' },
    });
    expect(result).toMatchObject({
      inboxId: 11,
      inboxName: 'Lucas',
      ownNumber: null,
      numberStatus: 'UNKNOWN',
    });
  });
  it('uses the safe server projection for Broker inboxes, without trusting native fallback data', () => {
    expect(
      inboxOrigin(
        {
          id: 11,
          name: 'Lucas',
          jrc_broker_bound: true,
          phone_number: '+15550000099',
          conversation_origin: {
            own_number: '+15550000001',
            number_status: 'VERIFIED',
            verified_at: '2026-11-05T12:00:00Z',
            valid_until: '2026-11-05T12:15:00Z',
          },
        },
        Date.parse('2026-11-05T12:01:00Z')
      )
    ).toMatchObject({ ownNumber: '+15550000001', numberStatus: 'VERIFIED' });
    expect(
      inboxOrigin({
        id: 11,
        jrc_broker_bound: true,
        conversation_origin: {
          own_number: '+15550000001',
          number_status: 'STALE',
        },
      }).ownNumber
    ).toBeNull();
  });
  it('expires a cached Broker identity while the attendance screen remains open', () => {
    const inbox = {
      id: 11,
      name: 'Lucas',
      jrc_broker_bound: true,
      conversation_origin: {
        own_number: '+15550000001',
        number_status: 'VERIFIED',
        verified_at: '2026-11-05T12:00:00Z',
        valid_until: '2026-11-05T12:15:00Z',
      },
    };
    expect(
      inboxOrigin(inbox, Date.parse('2026-11-05T12:14:59Z')).ownNumber
    ).toBe('+15550000001');
    expect(
      inboxOrigin(inbox, Date.parse('2026-11-05T12:15:00Z'))
    ).toMatchObject({ ownNumber: null, numberStatus: 'STALE' });
  });
  it('shows native WhatsApp numbers and rejects invalid number data', () => {
    expect(
      inboxOrigin({
        id: 11,
        phone_number: '+15550000001',
        channel_type: 'Channel::Whatsapp',
      }).ownNumber
    ).toBe('+15550000001');
    expect(
      inboxOrigin({
        id: 11,
        phone_number: 'private-secret',
        channel_type: 'Channel::Whatsapp',
      }).ownNumber
    ).toBeNull();
  });
  it('uses the newest real message rather than the conversation creation date or activity events', () => {
    expect(
      conversationMessageTimestamp({
        created_at: 1,
        timestamp: 500,
        messages: [
          { created_at: 90, message_type: 0 },
          { created_at: 300, message_type: 2 },
          { created_at: 80, message_type: 1 },
        ],
        last_non_activity_message: { created_at: 100, message_type: 1 },
      })
    ).toBe(100);
  });
  it('formats one clock value, Yesterday or a date instead of two unrelated conversation ages', () => {
    const now = Date.parse('2026-11-05T12:00:00Z');
    expect(
      messageClock(
        Date.parse('2026-11-05T10:35:00Z') / 1000,
        now,
        'en',
        'Yesterday',
        'UTC'
      )
    ).toBe('10:35');
    expect(
      messageClock(
        Date.parse('2026-11-04T10:00:00Z') / 1000,
        now,
        'en',
        'Yesterday',
        'UTC'
      )
    ).toBe('Yesterday');
    expect(messageClock(null, now, 'en', 'Yesterday', 'UTC')).toBe('');
  });
});
