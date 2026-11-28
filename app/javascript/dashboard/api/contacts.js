/* global axios */
import ApiClient from './ApiClient';

export const buildContactParams = (
  page,
  sortAttr,
  label,
  search,
  directoryView,
  directory
) => {
  let params = `include_contact_inboxes=false&page=${page}&sort=${sortAttr}`;
  if (search) {
    params = `${params}&q=${search}`;
  }
  if (label) {
    params = `${params}&labels[]=${label}`;
  }
  if (directoryView) {
    params = `${params}&directory_view=${encodeURIComponent(directoryView)}`;
  }
  if (directory) {
    const options = new URLSearchParams({ directory: 'true' });
    if (directory.ownerId) options.set('directory_owner_id', directory.ownerId);
    if (directory.inboxId) options.set('directory_inbox_id', directory.inboxId);
    params = `${params}&${options}`;
  }
  return params;
};

class ContactAPI extends ApiClient {
  constructor() {
    super('contacts', { accountScoped: true });
  }

  get(
    page,
    sortAttr = 'name',
    label = '',
    directoryView = '',
    directory = undefined
  ) {
    let requestURL = `${this.url}?${buildContactParams(
      page,
      sortAttr,
      label,
      '',
      directoryView,
      directory
    )}`;
    return axios.get(requestURL);
  }

  show(id) {
    return axios.get(`${this.url}/${id}?include_contact_inboxes=false`);
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}?include_contact_inboxes=false`, data);
  }

  getConversations(contactId, { inboxId } = {}) {
    const params = inboxId ? { inbox_id: inboxId } : {};
    return axios.get(`${this.url}/${contactId}/conversations`, { params });
  }

  getAttachments(contactId, page = 1) {
    return axios.get(`${this.url}/${contactId}/attachments`, {
      params: { page },
    });
  }

  getContactableInboxes(contactId) {
    return axios.get(`${this.url}/${contactId}/contactable_inboxes`);
  }

  getContactLabels(contactId) {
    return axios.get(`${this.url}/${contactId}/labels`);
  }

  initiateCall(contactId, inboxId, conversationId = null) {
    return axios.post(`${this.url}/${contactId}/call`, {
      inbox_id: inboxId,
      conversation_id: conversationId,
    });
  }

  updateContactLabels(contactId, labels) {
    return axios.post(`${this.url}/${contactId}/labels`, { labels });
  }

  search(search = '', page = 1, sortAttr = 'name', label = '', options = {}) {
    let requestURL = `${this.url}/search?${buildContactParams(
      page,
      sortAttr,
      label,
      search,
      options.directoryView,
      options.directory
    )}`;
    return axios.get(requestURL, { signal: options.signal });
  }

  active(
    page = 1,
    sortAttr = 'name',
    directoryView = '',
    directory = undefined
  ) {
    let requestURL = `${this.url}/active?${buildContactParams(page, sortAttr, '', '', directoryView, directory)}`;
    return axios.get(requestURL);
  }

  filter(
    // eslint-disable-next-line default-param-last
    page = 1,
    // eslint-disable-next-line default-param-last
    sortAttr = 'name',
    queryPayload,
    directoryView = '',
    directory = undefined
  ) {
    let requestURL = `${this.url}/filter?${buildContactParams(page, sortAttr, '', '', directoryView, directory)}`;
    return axios.post(requestURL, queryPayload);
  }

  importContacts(file) {
    const formData = new FormData();
    formData.append('import_file', file);
    return axios.post(`${this.url}/import`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  destroyCustomAttributes(contactId, customAttributes) {
    return axios.post(`${this.url}/${contactId}/destroy_custom_attributes`, {
      custom_attributes: customAttributes,
    });
  }

  destroyAvatar(contactId) {
    return axios.delete(`${this.url}/${contactId}/avatar`);
  }

  exportContacts(queryPayload) {
    return axios.post(`${this.url}/export`, queryPayload);
  }
}

export default new ContactAPI();
