/* global axios */

import ApiClient from './ApiClient';

class CannedResponse extends ApiClient {
  constructor() {
    super('canned_responses', { accountScoped: true });
  }

  get({ searchKey }) {
    const url = searchKey
      ? `${this.url}?search=${encodeURIComponent(searchKey)}`
      : this.url;
    return axios.get(url);
  }

  preview(id, conversationId) {
    return axios.post(`${this.url}/${id}/preview`, {
      conversation_id: conversationId,
    });
  }

  file(id) {
    return axios.get(`${this.url}/${id}/file`, { responseType: 'blob' });
  }

  deliver(id, values) {
    return axios.post(`${this.url}/${id}/deliver`, values);
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
