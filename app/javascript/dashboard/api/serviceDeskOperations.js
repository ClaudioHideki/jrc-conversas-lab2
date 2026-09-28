/* global axios */
import { createServiceDeskOperationsClient } from './serviceDeskOperationsClient';
export default createServiceDeskOperationsClient({
  get: (...args) => axios.get(...args),
  post: (...args) => axios.post(...args),
  patch: (...args) => axios.patch(...args),
});
