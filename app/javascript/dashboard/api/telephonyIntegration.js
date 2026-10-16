/* global axios */
import ApiClient from './ApiClient';

class TelephonyIntegrationAPI extends ApiClient {
  constructor() {
    super('telephony_integration', { accountScoped: true });
  }

  save(data) {
    return axios.patch(this.url, data);
  }

  testConnection() {
    return axios.post(`${this.url}/test_connection`);
  }

  synchronize() {
    return axios.post(`${this.url}/synchronize`);
  }
}
export default new TelephonyIntegrationAPI();
