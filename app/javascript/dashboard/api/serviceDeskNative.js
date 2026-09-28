/* global axios */
import { createServiceDeskNativeClient } from './serviceDeskNativeClient.js';
export default createServiceDeskNativeClient({ get: (...args) => axios.get(...args) });
