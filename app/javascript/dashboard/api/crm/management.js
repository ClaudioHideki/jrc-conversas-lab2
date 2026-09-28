/* global axios */
import ApiClient from '../ApiClient';

const managementAPI = new ApiClient('crm/management', { accountScoped: true });
managementAPI.list = params => axios.get(managementAPI.url, { params });

export default managementAPI;
