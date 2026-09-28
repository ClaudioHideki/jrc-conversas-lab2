/* global axios */
import { createServiceDeskClient } from './serviceDeskClient';
// Uses the native authenticated Axios instance; no alternate tokens/session.
export default createServiceDeskClient({ get: (...args) => axios.get(...args) });
