/* global axios */

import ApiClient from './ApiClient';

class CannedResponse extends ApiClient {
  constructor() {
    super('canned_responses', { accountScoped: true });
  }

  scopedUrl(accountId) {
    if (accountId === undefined) return this.url;
    if (!Number.isSafeInteger(Number(accountId)) || Number(accountId) <= 0)
      throw new Error('INVALID_ACCOUNT');
    return `/api/v1/accounts/${Number(accountId)}/canned_responses`;
  }

  get({ searchKey, accountId }) {
    const base = this.scopedUrl(accountId);
    const url = searchKey
      ? `${base}?search=${encodeURIComponent(searchKey)}`
      : base;
    return axios.get(url);
  }

  preview(id, conversationId, accountId) {
    return axios.post(`${this.scopedUrl(accountId)}/${id}/preview`, {
      conversation_id: conversationId,
    });
  }

  file(id, accountId, expected = {}) {
    return axios.get(`${this.scopedUrl(accountId)}/${id}/file`, {
      responseType: 'blob',
      params: expected,
    });
  }

  deliver(id, values, accountId) {
    return axios.post(`${this.scopedUrl(accountId)}/${id}/deliver`, values);
  }

  static payload(values) {
    if (!values.file && !values.remove_file) return values;
    const data = new FormData();
    ['short_code', 'content', 'file', 'remove_file'].forEach(key => {
      if (values[key] !== undefined && values[key] !== null)
        data.append(`canned_response[${key}]`, values[key]);
    });
    return data;
  }

  create(values) {
    return axios.post(this.url, CannedResponse.payload(values));
  }

  update(id, values) {
    return axios.patch(`${this.url}/${id}`, CannedResponse.payload(values));
  }
}

export default new CannedResponse();
