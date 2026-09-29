/* global axios */
import ApiClient from '../ApiClient';
const make = path => {
  const api = new ApiClient(`crm/${path}`, { accountScoped: true });
  api.list = params => axios.get(api.url, { params });
  api.create = data => axios.post(api.url, data);
  api.update = (id, data) => axios.patch(`${api.url}/${id}`, data);
  return api;
};
const uploadFiles = (url, files, extra = {}) => {
  const data = new FormData();
  Array.from(files || []).forEach(file => data.append('files[]', file));
  Object.entries(extra).forEach(([key, value]) => data.append(key, value));
  return axios.post(url, data, { headers: { 'Content-Type': 'multipart/form-data' } });
};

export const salesOrdersAPI = make('sales_orders');
salesOrdersAPI.preview = data => axios.post(`${salesOrdersAPI.url}/preview`, data);
salesOrdersAPI.show = id => axios.get(`${salesOrdersAPI.url}/${id}`);
salesOrdersAPI.pdf = id => axios.get(`${salesOrdersAPI.url}/${id}/pdf`, { responseType: 'blob' });
salesOrdersAPI.uploadAttachments = (id, files) => uploadFiles(`${salesOrdersAPI.url}/${id}/attachments`, files);
salesOrdersAPI.downloadAttachment = (id, attachmentId) => axios.get(`${salesOrdersAPI.url}/${id}/attachments/${attachmentId}`, { responseType: 'blob' });

export const contractsAPI = make('contracts');
contractsAPI.show = id => axios.get(`${contractsAPI.url}/${id}`);
contractsAPI.pdf = id => axios.get(`${contractsAPI.url}/${id}/pdf`, { responseType: 'blob' });
contractsAPI.history = id => axios.get(`${contractsAPI.url}/${id}/history`);
contractsAPI.uploadDocuments = (id, files) => uploadFiles(`${contractsAPI.url}/${id}/documents`, files);
contractsAPI.downloadDocument = (id, attachmentId) => axios.get(`${contractsAPI.url}/${id}/documents/${attachmentId}`, { responseType: 'blob' });
contractsAPI.downloadSignedDocument = id => axios.get(`${contractsAPI.url}/${id}/signed_document`, { responseType: 'blob' });
contractsAPI.prepareSignature = (id, data) => axios.post(`${contractsAPI.url}/${id}/prepare_signature`, data);
contractsAPI.sendForSignature = (id, data = {}) => axios.post(`${contractsAPI.url}/${id}/send_for_signature`, data);
contractsAPI.registerManualSignature = (id, payload) => {
  const data = new FormData();
  data.append('signed_by_name', payload.signed_by_name || '');
  if (payload.signed_at) data.append('signed_at', payload.signed_at);
  if (payload.signed_file) data.append('signed_file', payload.signed_file);
  return axios.post(`${contractsAPI.url}/${id}/register_manual_signature`, data, { headers: { 'Content-Type': 'multipart/form-data' } });
};
contractsAPI.renew = (id, data) => axios.post(`${contractsAPI.url}/${id}/renew`, data);
contractsAPI.addendum = (id, data) => axios.post(`${contractsAPI.url}/${id}/addendum`, data);

export const commissionsAPI = make('commissions');
commissionsAPI.summary = params => axios.get(`${commissionsAPI.url}/summary`, { params });
commissionsAPI.history = params => axios.get(`${commissionsAPI.url}/history`, { params });
export const commissionProgramsAPI = make('commission_programs');
commissionProgramsAPI.simulate = data => axios.post(`${commissionProgramsAPI.url}/simulate`, data);

export const backofficeAPI = make('backoffice_requests');
backofficeAPI.show = id => axios.get(`${backofficeAPI.url}/${id}`);
backofficeAPI.summary = () => axios.get(`${backofficeAPI.url}/summary`);
backofficeAPI.advance = id => axios.post(`${backofficeAPI.url}/${id}/advance`);
backofficeAPI.uploadDocuments = (id, files) => uploadFiles(`${backofficeAPI.url}/${id}/documents`, files);
backofficeAPI.downloadDocument = (id, attachmentId) => axios.get(`${backofficeAPI.url}/${id}/documents/${attachmentId}`, { responseType: 'blob' });
backofficeAPI.documentStatus = (id, data) => axios.post(`${backofficeAPI.url}/${id}/document_status`, data);
backofficeAPI.addIssue = (id, data) => axios.post(`${backofficeAPI.url}/${id}/issues`, data);
backofficeAPI.resolveIssue = (id, issueId) => axios.post(`${backofficeAPI.url}/${id}/resolve_issue`, { issue_id: issueId });
backofficeAPI.confirmProvisioning = (id, data) => axios.post(`${backofficeAPI.url}/${id}/confirm_provisioning`, data);
backofficeAPI.reopen = (id, data = {}) => axios.post(`${backofficeAPI.url}/${id}/reopen`, data);

export const invoicesAPI = make('invoices');
invoicesAPI.show = id => axios.get(`${invoicesAPI.url}/${id}`);
export const paymentsAPI = make('payments');
export const contractTemplatesAPI = make('contract_templates');
contractTemplatesAPI.delete = id => axios.delete(`${contractTemplatesAPI.url}/${id}`);
export const goalsAPI = make('goals');
goalsAPI.dashboard = params => axios.get(`${goalsAPI.url}/dashboard`, { params });

export const customersAPI = (() => {
  const api = new ApiClient('crm/customers', { accountScoped: true });
  api.show = id => axios.get(`${api.url}/${id}`);
  return api;
})();
