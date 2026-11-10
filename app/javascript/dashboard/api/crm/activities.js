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

// Explicit account and bounded window; existing list consumers retain arrays.
activitiesAPI.calendarPageInAccount = (accountId, params, options = {}) =>
  axios.get(activitiesAPI.urlForAccount(accountId), {
    ...options,
    params: { ...params, calendar_page: 1 },
  });

export default activitiesAPI;

activitiesAPI.completeInAccount = (accountId, id, options) =>
  axios.post(
    `${activitiesAPI.urlForAccount(accountId)}/${id}/complete`,
    {},
    options
  );
