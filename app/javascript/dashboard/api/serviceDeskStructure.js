/* global axios */
import { createServiceDeskStructureClient } from './serviceDeskStructureClient';
export default createServiceDeskStructureClient({
  get: (...args) => axios.get(...args),
  post: (...args) => axios.post(...args),
  patch: (...args) => axios.patch(...args),
});
