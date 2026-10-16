/* global axios */

import ApiClient from './ApiClient';

class CallHistoryAPI extends ApiClient {
  constructor() {
    super('call_history', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }

  recording(id, options = {}) {
    return axios.get(`${this.url}/${id}/recording`, {
      responseType: 'blob',
      signal: options.signal,
    });
  }

  recordingMetadata(id) {
    return axios.get(`${this.url}/${id}/recording_metadata`);
  }
}

export default new CallHistoryAPI();
