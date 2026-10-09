import { API } from 'widget/helpers/axios';
import {
  portalIdentity,
  portalIdentityHeaders,
} from 'widget/helpers/serviceDeskIdentityProof';
const root = '/api/v1/widget/service_desk';
const id = value => {
  if (!/^[1-9]\d{0,18}$/.test(String(value)))
    throw new TypeError('Invalid portal identifier');
  return String(value);
};
const options = (websiteToken, signal, requestKey) => ({
  signal,
  timeout: 20000,
  params: { website_token: websiteToken },
  headers: {
    ...portalIdentityHeaders(API.defaults.headers.common['X-Auth-Token']),
    ...(requestKey ? { 'Idempotency-Key': requestKey } : {}),
  },
});
const command = (websiteToken, values, files) => {
  if (!files.length) return { website_token: websiteToken, ...values };
  const form = new FormData();
  form.append('website_token', websiteToken);
  Object.entries(values).forEach(([key, value]) =>
    form.append(
      key,
      value && typeof value === 'object' ? JSON.stringify(value) : value
    )
  );
  files.forEach(file => form.append('files[]', file));
  return form;
};
const searchOptions = (websiteToken, query, signal) => {
  if (typeof query !== 'string' || query.length > 200)
    throw new TypeError('Invalid portal search');
  const value = options(websiteToken, signal);
  return { ...value, params: { ...value.params, q: query } };
};
export default {
  identity: () => portalIdentity(API.defaults.headers.common['X-Auth-Token']),
  hasIdentityProof: () =>
    !!portalIdentity(API.defaults.headers.common['X-Auth-Token']),
  services: (websiteToken, signal) =>
    API.get(`${root}/services`, options(websiteToken, signal)).then(
      response => response.data
    ),
  tickets: (websiteToken, signal, query = '') =>
    API.get(`${root}/tickets`, searchOptions(websiteToken, query, signal)).then(
      response => response.data
    ),
  knowledge: (websiteToken, query, signal) =>
    API.get(
      `${root}/knowledge`,
      searchOptions(websiteToken, query, signal)
    ).then(response => response.data),
  ticket: (websiteToken, ticket, signal) =>
    API.get(
      `${root}/tickets/${id(ticket)}`,
      options(websiteToken, signal)
    ).then(response => response.data),
  create: (websiteToken, ticket, files, key, signal) =>
    API.post(
      `${root}/tickets`,
      command(websiteToken, { ticket }, files),
      options(websiteToken, signal, key)
    ).then(response => response.data),
  reply: (websiteToken, ticket, body, conversation, files, key, signal) =>
    API.post(
      `${root}/tickets/${id(ticket)}/replies`,
      command(websiteToken, { body, conversation_id: id(conversation) }, files),
      options(websiteToken, signal, key)
    ).then(response => response.data),
  attachment: (websiteToken, ticket, kind, record, file, signal) => {
    if (!['notes', 'messages'].includes(kind))
      throw new TypeError('Invalid portal attachment source');
    return API.get(
      `${root}/tickets/${id(ticket)}/${kind}/${id(record)}/attachments/${id(file)}`,
      { ...options(websiteToken, signal), responseType: 'blob' }
    ).then(response => response.data);
  },
};
