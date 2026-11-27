import { canonicalId } from './access';

const id = value => {
  if (!['string', 'number'].includes(typeof value))
    throw new TypeError('Invalid native recording intake identity');
  const result = canonicalId(value);
  if (!result) throw new TypeError('Invalid native recording intake identity');
  return result;
};

export function decodeRecordingTicketSource(
  data,
  accountId,
  userId,
  recordingId
) {
  if (!data || data.contract_version !== 1)
    throw new TypeError('Invalid intake contract');
  const result = Object.fromEntries(
    [
      'account_id',
      'user_id',
      'recording_id',
      'call_session_id',
      'contact_id',
      'service_desk_unit_id',
    ].map(field => [field, id(data[field])])
  );
  if (
    result.account_id !== id(accountId) ||
    result.user_id !== id(userId) ||
    result.recording_id !== id(recordingId)
  )
    throw new TypeError('Native recording intake scope changed');
  if (
    typeof data.call_id !== 'string' ||
    !data.call_id.trim() ||
    [...data.call_id].some(character => character.charCodeAt(0) < 32)
  )
    throw new TypeError('Invalid native call identity');
  return Object.freeze({
    ...result,
    contract_version: 1,
    call_id: data.call_id,
  });
}

export function selectedRecordingForTicket(source, accountId, userId, payload) {
  if (!source) throw new TypeError('Native recording intake is unavailable');
  const checked = decodeRecordingTicketSource(
    source,
    accountId,
    userId,
    source.recording_id
  );
  if (
    id(payload.unit_id) !== checked.service_desk_unit_id ||
    id(payload.ticket?.requester_id) !== checked.contact_id
  )
    throw new TypeError('Native recording intake destination changed');
  return checked.recording_id;
}
