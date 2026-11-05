import { isWhatsAppInbox } from './inbox';

const phone = value =>
  typeof value === 'string' && /^\+?[1-9]\d{7,14}$/.test(value)
    ? `+${value.replace(/^\+/, '')}`
    : null;

// The source is always an authorized inbox projection, never a contact or assignee.
export const inboxOrigin = (inbox = {}, now = Date.now()) => {
  const source = inbox.conversation_origin;
  const broker = inbox.jrc_broker_bound === true;
  const validUntil = Date.parse(source?.valid_until);
  const fresh = Number.isFinite(validUntil) && now < validUntil;
  const ownNumber = broker
    ? fresh && source?.number_status === 'VERIFIED' && phone(source.own_number)
    : isWhatsAppInbox(inbox) && phone(inbox.phone_number);
  const unknownStatus = ['STALE', 'VERIFIED'].includes(source?.number_status)
    ? 'STALE'
    : 'UNKNOWN';
  return {
    inboxId: inbox.id,
    inboxName: inbox.name || '',
    ownNumber: ownNumber || null,
    numberStatus: ownNumber ? 'VERIFIED' : unknownStatus,
    verifiedAt: source?.verified_at || null,
  };
};

const seconds = value => {
  if (typeof value === 'number')
    return Number.isFinite(value) && value > 0 && value <= 253402300799
      ? value
      : null;
  if (typeof value === 'string') {
    const result = Date.parse(value) / 1000;
    return Number.isFinite(result) && result > 0 && result <= 253402300799
      ? result
      : null;
  }
  return null;
};

export const conversationMessageTimestamp = chat => {
  const candidates = [...(chat.messages || []), chat.last_non_activity_message]
    .filter(item => item && item.message_type !== 2)
    .map(item => seconds(item.created_at))
    .filter(Boolean);
  return candidates.length
    ? Math.max(...candidates)
    : seconds(chat.last_activity_at) ||
        seconds(chat.timestamp) ||
        seconds(chat.created_at);
};

export const messageClock = (timestamp, now, locale, yesterday, timeZone) => {
  if (!Number.isFinite(timestamp) || timestamp <= 0) return '';
  const date = new Date(timestamp * 1000);
  const today = new Date(now);
  const calendar = value =>
    new Intl.DateTimeFormat('en-CA', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(value);
  if (calendar(date) === calendar(today)) {
    return new Intl.DateTimeFormat(locale, {
      timeZone,
      hour: '2-digit',
      minute: '2-digit',
      hourCycle: 'h23',
    }).format(date);
  }
  const parts = new Intl.DateTimeFormat('en', {
    timeZone,
    year: 'numeric',
    month: 'numeric',
    day: 'numeric',
  }).formatToParts(today);
  const part = name => Number(parts.find(item => item.type === name).value);
  const previous = new Date(
    Date.UTC(part('year'), part('month') - 1, part('day') - 1, 12)
  );
  const previousDay = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'UTC',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(previous);
  if (calendar(date) === previousDay) return yesterday;
  return new Intl.DateTimeFormat(locale, {
    timeZone,
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  }).format(date);
};
