/* global axios */
import ApiClient from '../ApiClient';

const proposalsAPI = new ApiClient('crm/proposals', { accountScoped: true });
proposalsAPI.list = params => axios.get(proposalsAPI.url, { params });
proposalsAPI.sendProposal = (id, channel = 'auto') =>
  axios.post(`${proposalsAPI.url}/${id}/send_proposal`, { channel });
proposalsAPI.pdf = id =>
  axios.get(`${proposalsAPI.url}/${id}/pdf`, { responseType: 'blob' });
proposalsAPI.pdfUrl = (id, download = false) =>
  `${proposalsAPI.url}/${id}/pdf${download ? '?download=1' : ''}`;
proposalsAPI.accept = (id, payload) =>
  axios.post(`${proposalsAPI.url}/${id}/accept`, payload);
proposalsAPI.reject = (id, reason) =>
  axios.post(`${proposalsAPI.url}/${id}/reject`, { reason });
proposalsAPI.cancel = id => axios.post(`${proposalsAPI.url}/${id}/cancel`);
proposalsAPI.duplicate = id =>
  axios.post(`${proposalsAPI.url}/${id}/duplicate`);
proposalsAPI.requestApproval = id =>
  axios.post(`${proposalsAPI.url}/${id}/request_approval`);
proposalsAPI.approve = (id, approvalType, decision = 'approved') =>
  axios.post(`${proposalsAPI.url}/${id}/approve`, {
    approval_type: approvalType,
    decision,
  });
proposalsAPI.createItem = (proposalId, data) =>
  axios.post(`${proposalsAPI.url}/${proposalId}/items`, data);
proposalsAPI.updateItem = (proposalId, itemId, data) =>
  axios.patch(`${proposalsAPI.url}/${proposalId}/items/${itemId}`, data);
proposalsAPI.deleteItem = (proposalId, itemId) =>
  axios.delete(`${proposalsAPI.url}/${proposalId}/items/${itemId}`);

export default proposalsAPI;
