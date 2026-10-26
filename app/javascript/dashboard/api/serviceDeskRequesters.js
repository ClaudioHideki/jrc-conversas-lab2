/* global axios */
import ApiClient from './ApiClient';

class ServiceDeskRequesters extends ApiClient {
  constructor() {
    super('jrc_service_desk/requester_people', { accountScoped: true });
  }

  search(params) {
    return axios.get(this.url, { params });
  }

  validate(id, params) {
    return axios.get(`${this.url}/${id}`, { params });
  }

  register(body) {
    return axios.post(this.url, body);
  }

  link(id, body) {
    return axios.patch(`${this.url}/${id}/link`, body);
  }
}

export default new ServiceDeskRequesters();
