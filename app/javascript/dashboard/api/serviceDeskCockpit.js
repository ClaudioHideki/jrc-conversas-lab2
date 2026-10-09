/* global axios */
import { canonicalId } from '../routes/dashboard/serviceDesk/helpers/access';
const id = value => {
  const result = canonicalId(value);
  if (!result) throw new TypeError('Invalid identifier');
  return result;
};
const base = (account, ticket) =>
  `/api/v1/accounts/${id(account)}/jrc_service_desk/tickets/${id(ticket)}`;
const options = (signal, key) => ({
  signal,
  timeout: 30000,
  ...(key ? { headers: { 'Idempotency-Key': key } } : {}),
});
function interactionPayload(note, files, receipt) {
  let payload = { note, ...(receipt ? { preview_receipt: receipt } : {}) };
  if (files.length) {
    payload = new FormData();
    Object.entries(note).forEach(([field, value]) => {
      if (Array.isArray(value))
        value.forEach(item => payload.append(`note[${field}][]`, item));
      else if (value && typeof value === 'object')
        Object.entries(value).forEach(([channel, conversation]) =>
          payload.append(`note[${field}][${channel}]`, conversation)
        );
      else if (value !== null) payload.append(`note[${field}]`, value);
    });
    files.forEach(file => payload.append('files[]', file));
    if (receipt) payload.append('preview_receipt', receipt);
  }
  return payload;
}

export default {
  claimNext: (account, unit, key, signal) =>
    axios
      .post(
        `/api/v1/accounts/${id(account)}/jrc_service_desk/claim_next`,
        { unit_id: id(unit) },
        options(signal, key)
      )
      .then(r => r.data),
  read: (account, ticket, signal) =>
    axios
      .get(`${base(account, ticket)}/cockpit`, options(signal))
      .then(r => r.data),
  composer: (account, ticket, signal) =>
    axios
      .get(`${base(account, ticket)}/composer_options`, options(signal))
      .then(r => r.data),
  recipientPreferences: (account, ticket, signal) =>
    axios
      .get(`${base(account, ticket)}/recipient_preferences`, options(signal))
      .then(r => r.data),
  updateRecipientPreferences: (account, ticket, channels, signal) =>
    axios
      .patch(
        `${base(account, ticket)}/recipient_preferences`,
        { channels },
        options(signal)
      )
      .then(r => r.data),
  preview: (account, ticket, note, files, signal) =>
    axios
      .post(
        `${base(account, ticket)}/interaction_preview`,
        interactionPayload(note, files),
        options(signal)
      )
      .then(r => r.data),
  timeline: (account, ticket, cursor, signal) =>
    axios
      .get(`${base(account, ticket)}/timeline`, {
        ...options(signal),
        params: { ...(cursor ? { cursor } : {}) },
      })
      .then(r => r.data),
  timelineAttachment: (account, ticket, kind, record, attachment, signal) => {
    if (!['note', 'message', 'call'].includes(kind))
      throw new TypeError('Invalid attachment source');
    return axios
      .get(
        `${base(account, ticket)}/timeline/${kind}/${id(record)}/attachments/${id(attachment)}`,
        { ...options(signal), responseType: 'blob' }
      )
      .then(r => r.data);
  },
  resendPreview: (account, ticket, delivery, reason, signal) =>
    axios
      .post(
        `${base(account, ticket)}/notification_deliveries/${id(delivery)}/resend_preview`,
        { reason },
        options(signal)
      )
      .then(r => r.data),
  resend: (account, ticket, delivery, reason, receipt, key, signal) =>
    axios
      .post(
        `${base(account, ticket)}/notification_deliveries/${id(delivery)}/resend`,
        { reason, receipt, idempotency_key: key },
        options(signal)
      )
      .then(r => r.data),
  reconcile: (account, ticket, delivery, signal) =>
    axios
      .post(
        `${base(account, ticket)}/notification_deliveries/${id(delivery)}/reconcile`,
        {},
        options(signal)
      )
      .then(r => r.data),
  policies: (account, unit, signal) =>
    axios
      .get(
        `/api/v1/accounts/${id(account)}/jrc_service_desk/notification_policies`,
        { ...options(signal), params: { unit_id: id(unit) } }
      )
      .then(r => r.data),
  publishPolicy: (account, unit, policy, signal) =>
    axios
      .post(
        `/api/v1/accounts/${id(account)}/jrc_service_desk/notification_policies`,
        { unit_id: id(unit), policy },
        options(signal)
      )
      .then(r => r.data),
  interaction: (account, ticket, note, files, key, signal, receipt) => {
    const payload = interactionPayload(note, files, receipt);
    return axios
      .post(
        `${base(account, ticket)}/interactions`,
        payload,
        options(signal, key)
      )
      .then(r => r.data);
  },
  task: (account, ticket, task, key, signal) =>
    axios
      .post(`${base(account, ticket)}/tasks`, { task }, options(signal, key))
      .then(r => r.data),
  updateTask: (account, ticket, record, task, signal) =>
    axios
      .patch(
        `${base(account, ticket)}/tasks/${id(record.id)}`,
        { task, expected_lock_version: record.lock_version },
        options(signal)
      )
      .then(r => r.data),
  approval: (account, ticket, approval, key, signal) =>
    axios
      .post(
        `${base(account, ticket)}/approvals`,
        { approval },
        options(signal, key)
      )
      .then(r => r.data),
  decision: (account, ticket, record, decision, signal) =>
    axios
      .post(
        `${base(account, ticket)}/approvals/${id(record.id)}/decision`,
        { decision, expected_lock_version: record.lock_version },
        options(signal)
      )
      .then(r => r.data),
  escalateApproval: (account, ticket, record, escalation, signal) =>
    axios
      .post(
        `${base(account, ticket)}/approvals/${id(record.id)}/escalate`,
        { escalation, expected_lock_version: record.lock_version },
        options(signal)
      )
      .then(r => r.data),
  evaluateClocks: (account, ticket, signal) =>
    axios
      .post(`${base(account, ticket)}/evaluate_clocks`, {}, options(signal))
      .then(r => r.data),
  attachment: (account, ticket, note, attachment, signal) =>
    axios
      .get(
        `${base(account, ticket)}/notes/${id(note)}/attachments/${id(attachment)}`,
        { ...options(signal), responseType: 'blob' }
      )
      .then(r => r.data),
};
