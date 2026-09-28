/* global axios */
import { createServiceDeskLifecycleClient } from './serviceDeskLifecycleClient';
export default createServiceDeskLifecycleClient({ get: (...args) => axios.get(...args), post: (...args) => axios.post(...args) });
