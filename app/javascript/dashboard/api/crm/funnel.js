/* global axios */
import ApiClient from '../ApiClient';

class FunnelAPI extends ApiClient {
  constructor() {
    super('crm/funnel', { accountScoped: true });
  }

  show(params, { accountId, signal }) {
    return axios.get(this.urlForAccount(accountId), { params, signal });
  }
}

export default new FunnelAPI();
