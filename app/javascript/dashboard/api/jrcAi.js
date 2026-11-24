/* global axios */
import ApiClient from './ApiClient';

class JrcAiAPI extends ApiClient {
  constructor() {
    super('jrc_ai', { accountScoped: true });
  }

  cockpit(period = 'today') {
    return axios.get(`${this.url}/cockpit`, { params: { period } });
  }

  agents(period = 'today') {
    return axios.get(`${this.url}/agents`, { params: { period } });
  }

  providers() {
    return axios.get(`${this.url}/providers`);
  }

  createProvider(payload) {
    return axios.post(`${this.url}/providers`, { provider: payload });
  }

  updateProvider(id, payload) {
    return axios.patch(`${this.url}/providers/${id}`, { provider: payload });
  }

  deleteProvider(id) {
    return axios.delete(`${this.url}/providers/${id}`);
  }

  providerModels(payload, id) {
    return axios.post(`${this.url}/providers/model_catalogue`, {
      provider: payload,
      ...(id ? { id } : {}),
    });
  }

  validateProvider(id) {
    return axios.post(`${this.url}/providers/${id}/validate_configuration`);
  }

  makeDefault(id) {
    return axios.post(`${this.url}/providers/${id}/make_default`);
  }

  usage() {
    return axios.get(`${this.url}/usage`);
  }
}

export default new JrcAiAPI();
