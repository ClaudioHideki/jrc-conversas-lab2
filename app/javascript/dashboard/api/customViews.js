/* global axios */
import ApiClient from './ApiClient';

class CustomViewsAPI extends ApiClient {
  constructor() {
    super('custom_filters', { accountScoped: true });
  }

  getCustomViewsByFilterType(type, options = {}) {
    const { accountId, ...requestOptions } = options;
    const url =
      accountId === undefined ? this.url : this.urlForAccount(accountId);
    return axios.get(`${url}?filter_type=${type}`, requestOptions);
  }

  deleteCustomViews(id, type) {
    return axios.delete(`${this.url}/${id}?filter_type=${type}`);
  }
}

export default new CustomViewsAPI();
