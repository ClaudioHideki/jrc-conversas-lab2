/* global axios */
import { createServiceDeskConfigurationClient } from './serviceDeskConfigurationClient';
export default createServiceDeskConfigurationClient({
  get: (...args) => axios.get(...args),
  post: (...args) => axios.post(...args),
  patch: (...args) => axios.patch(...args),
});
