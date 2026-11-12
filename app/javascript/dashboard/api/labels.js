/* global axios */
import CacheEnabledApiClient from './CacheEnabledApiClient';

class LabelsAPI extends CacheEnabledApiClient {
  constructor() {
    super('labels', { accountScoped: true });
  }

  // eslint-disable-next-line class-methods-use-this
  get cacheModelName() {
    return 'label';
  }

  getForAccount(accountId, options = {}) {
    return axios.get(this.urlForAccount(accountId), options);
  }
}

export default new LabelsAPI();
