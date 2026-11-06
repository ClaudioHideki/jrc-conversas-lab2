/* global axios */
import ApiClient from '../ApiClient';

const activitiesAPI = new ApiClient('crm/activities', { accountScoped: true });
activitiesAPI.list = params => axios.get(activitiesAPI.url, { params });
activitiesAPI.complete = id =>
  axios.post(`${activitiesAPI.url}/${id}/complete`);
activitiesAPI.showInAccount = (accountId, id, options) =>
  axios.get(`${activitiesAPI.urlForAccount(accountId)}/${id}`, options);
activitiesAPI.updateInAccount = (accountId, id, data, options) =>
  axios.patch(`${activitiesAPI.urlForAccount(accountId)}/${id}`, data, options);

export default activitiesAPI;
