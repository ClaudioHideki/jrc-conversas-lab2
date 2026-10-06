/* global axios */
// Explicit account binding prevents in-flight requests from following an account switch.
const base = accountId => {
  const value = String(accountId);
  if (!/^[1-9]\d*$/.test(value) || !Number.isSafeInteger(Number(value))) {
    throw new Error('Invalid account context');
  }
  return `/api/v1/accounts/${value}/relationship`;
};
const operationsBase = accountId => base(accountId).replace(/\/relationship$/, '/crm');
export default {
  metadata: (accountId, options) =>
    axios.get(`${base(accountId)}/metadata`, options),
  dashboard: (accountId, params, options) =>
    axios.get(`${base(accountId)}/dashboard`, { ...options, params }),
  team: (accountId, params, options) =>
    axios.get(`${base(accountId)}/team`, { ...options, params }),
  portfolio: (accountId, params, options) =>
    axios.get(`${base(accountId)}/portfolio`, { ...options, params }),
  customer: (accountId, id, options) =>
    axios.get(`${base(accountId)}/portfolio/${Number(id)}`, options),
  saveAssignment: (accountId, assignment, id) =>
    id
      ? axios.patch(`${base(accountId)}/portfolio/${Number(id)}`, {
          assignment,
        })
      : axios.post(`${base(accountId)}/portfolio`, { assignment }),
  channels: (accountId, id, options) =>
    axios.get(`${base(accountId)}/portfolio/${Number(id)}/channels`, options),
  recalculate: (accountId, id) =>
    axios.post(`${base(accountId)}/portfolio/${Number(id)}/recalculate`),
  activity: (accountId, id, activity) =>
    axios.post(`${base(accountId)}/portfolio/${Number(id)}/activity`, activity),
  recommendations: (accountId, id, options) =>
    axios.get(
      `${base(accountId)}/portfolio/${Number(id)}/recommendations`,
      options
    ),
  workContext: (accountId, id, params, options) =>
    axios.get(`${base(accountId)}/portfolio/${Number(id)}/work_context`, { ...options, params }),
  exportPortfolio: (accountId, params) =>
    axios.get(`${base(accountId)}/export`, { params, responseType: 'blob' }),
  exportHistory: (accountId, params) => axios.get(`${base(accountId)}/export_history`, { params, responseType: 'blob' }),
  portfolioBatch: (accountId, ids, fields) =>
    axios.post(`${base(accountId)}/portfolio/batch`, { ids, ...fields }),
  surveyLink: (accountId, id) => axios.get(`${base(accountId)}/surveys/${Number(id)}/link`),
  deliverSurvey: (accountId, id, conversationId) => axios.post(`${base(accountId)}/surveys/${Number(id)}/deliver`, { conversation_id: conversationId }),
  nativeCsat: (accountId, id, conversationId) => axios.post(`${base(accountId)}/portfolio/${Number(id)}/native_csat`, { conversation_id: conversationId }),
  records: (accountId, kind, params, options) =>
    axios.get(`${base(accountId)}/records/${kind}`, { ...options, params }),
  saveRecord: (accountId, kind, record, id) =>
    id
      ? axios.patch(`${base(accountId)}/records/${kind}/${Number(id)}`, {
          record,
        })
      : axios.post(`${base(accountId)}/records/${kind}`, { record }),
  opportunity: (accountId, kind, id, fields) =>
    axios.post(
      `${base(accountId)}/records/${kind}/${Number(id)}/opportunity`,
      fields
    ),
  batch: (accountId, ids, record) =>
    axios.post(`${base(accountId)}/actions/batch`, { ids, record }),
  configuration: (accountId, options) =>
    axios.get(`${base(accountId)}/configuration`, options),
  saveConfiguration: (accountId, fields) =>
    axios.patch(`${base(accountId)}/configuration`, fields),
  operationsQueues: (accountId, options) =>
    axios.get(`${operationsBase(accountId)}/operations_queues`, options),
  operationsPolicies: (accountId, options) =>
    axios.get(`${operationsBase(accountId)}/operations_sla_policies`, options),
  saveOperationsQueue: (accountId, operations_queue, id) =>
    id
      ? axios.patch(`${operationsBase(accountId)}/operations_queues/${Number(id)}`, { operations_queue })
      : axios.post(`${operationsBase(accountId)}/operations_queues`, { operations_queue }),
  saveOperationsPolicy: (accountId, operations_sla_policy, id) =>
    id
      ? axios.patch(`${operationsBase(accountId)}/operations_sla_policies/${Number(id)}`, { operations_sla_policy })
      : axios.post(`${operationsBase(accountId)}/operations_sla_policies`, { operations_sla_policy }),
  playbooks: (accountId, options) =>
    axios.get(`${base(accountId)}/playbooks`, options),
  savePlaybook: (accountId, playbook, id) =>
    id
      ? axios.patch(`${base(accountId)}/playbooks/${Number(id)}`, { playbook })
      : axios.post(`${base(accountId)}/playbooks`, { playbook }),
};
