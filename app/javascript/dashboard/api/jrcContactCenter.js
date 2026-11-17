/* global axios */

const base = accountId => {
  const value = String(accountId);
  if (!/^[1-9]\d*$/.test(value) || !Number.isSafeInteger(Number(value))) {
    throw new Error('Invalid account context');
  }
  return `/api/v1/accounts/${value}/jrc_contact_center`;
};

export default {
  configurationRecord: (accountId, resource, id) => {
    const paths = {
      units: 'units',
      queues: 'queues',
      memberships: 'queue_memberships',
      access_users: 'access_authorizations/users',
      access_teams: 'access_authorizations/teams',
    };
    if (!paths[resource] || !/^[1-9]\d*$/.test(String(id)))
      throw new Error('Invalid configuration context');
    return axios.get(`${base(accountId)}/${paths[resource]}/${Number(id)}`);
  },
  administration: accountId => axios.get(`${base(accountId)}/administration`),
  accessAuthorizations: (accountId, type, params = {}) => {
    if (!['users', 'teams'].includes(type))
      throw new Error('Invalid authority context');
    return axios.get(`${base(accountId)}/access_authorizations/${type}`, {
      params,
    });
  },
  saveAccessAuthorization: (accountId, type, id, authorization, options) => {
    if (!['users', 'teams'].includes(type))
      throw new Error('Invalid authority context');
    return axios.patch(
      `${base(accountId)}/access_authorizations/${type}/${Number(id)}`,
      { ...options, authorization }
    );
  },
  administrativeList: (accountId, section, params = {}) =>
    axios.get(
      `${base(accountId)}/administration/${encodeURIComponent(section)}`,
      { params }
    ),
  configurationAudits: (accountId, params = {}) =>
    axios.get(`${base(accountId)}/configuration_audits`, { params }),
  configurationAudit: (accountId, id) =>
    axios.get(`${base(accountId)}/configuration_audits/${Number(id)}`),
  exportConfigurationAudits: (accountId, params = {}) =>
    axios.get(`${base(accountId)}/configuration_audits/export`, {
      params,
      responseType: 'blob',
    }),
  acwPolicy: accountId => axios.get(`${base(accountId)}/acw_policy`),
  updateAcwPolicy: (accountId, limits, options = {}) =>
    axios.patch(`${base(accountId)}/acw_policy`, { ...options, limits }),
  qualifications: (accountId, params) =>
    axios.get(`${base(accountId)}/qualifications`, { params }),
  startQualification: (accountId, params) =>
    axios.post(`${base(accountId)}/qualifications`, params),
  completeQualification: (accountId, id, qualification) =>
    axios.patch(`${base(accountId)}/qualifications/${Number(id)}`, {
      qualification,
    }),
  agentState: accountId => axios.get(`${base(accountId)}/agent_state`),
  updateAgentState: (accountId, agentState) =>
    axios.patch(`${base(accountId)}/agent_state`, { agent_state: agentState }),
  supervisor: accountId => axios.get(`${base(accountId)}/supervisor`),
  operationalHealth: accountId =>
    axios.get(`${base(accountId)}/integrations/health`),
  commands: accountId => axios.get(`${base(accountId)}/commands`),
  createCommand: (accountId, command) =>
    axios.post(`${base(accountId)}/commands`, { command }),
  events: accountId => axios.get(`${base(accountId)}/events`),
  reprocessEvent: (accountId, id) =>
    axios.post(`${base(accountId)}/events/${Number(id)}/reprocess`),
  context: accountId =>
    axios.get(`${base(accountId)}/context`, { timeout: 30000 }),
  customerContext: (accountId, phone) =>
    axios.get(`${base(accountId)}/customer_context`, { params: { phone } }),
  units: (accountId, params = {}) =>
    axios.get(`${base(accountId)}/units`, { params }),
  saveUnit: (accountId, unit, id, options = {}) =>
    id
      ? axios.patch(`${base(accountId)}/units/${Number(id)}`, {
          ...options,
          unit,
        })
      : axios.post(`${base(accountId)}/units`, { unit }),
  queues: (accountId, params = {}) =>
    axios.get(`${base(accountId)}/queues`, { params }),
  queueMemberships: (accountId, params = {}) =>
    axios.get(`${base(accountId)}/queue_memberships`, { params }),
  saveQueueMembership: (accountId, queueMembership, id, options = {}) =>
    id
      ? axios.patch(`${base(accountId)}/queue_memberships/${Number(id)}`, {
          ...options,
          queue_membership: queueMembership,
        })
      : axios.post(`${base(accountId)}/queue_memberships`, {
          queue_membership: queueMembership,
        }),
  saveQueue: (accountId, queue, id, options = {}) =>
    id
      ? axios.patch(`${base(accountId)}/queues/${Number(id)}`, {
          ...options,
          queue,
        })
      : axios.post(`${base(accountId)}/queues`, { queue }),
  calls: (accountId, params = {}) =>
    axios.get(`${base(accountId)}/call_sessions`, { params, timeout: 30000 }),
  call: (accountId, id) =>
    axios.get(`${base(accountId)}/call_sessions/${Number(id)}`),
  saveCallObservations: (accountId, id, observations) =>
    axios.patch(`${base(accountId)}/call_sessions/${Number(id)}/observations`, {
      observations,
    }),
  callObservations: (accountId, id, params = {}) =>
    axios.get(`${base(accountId)}/call_sessions/${Number(id)}/observations`, {
      params,
    }),
  cases: (accountId, params = {}) =>
    axios.get(`${base(accountId)}/cases`, { params }),
  case: (accountId, id) => axios.get(`${base(accountId)}/cases/${Number(id)}`),
  createCase: (accountId, record) =>
    axios.post(`${base(accountId)}/cases`, { case: record }),
  updateCase: (accountId, id, record) =>
    axios.patch(`${base(accountId)}/cases/${Number(id)}`, { case: record }),
  callbacks: (accountId, params = {}) =>
    axios.get(`${base(accountId)}/callbacks`, { params }),
  createCallback: (accountId, callback) =>
    axios.post(`${base(accountId)}/callbacks`, { callback }),
  updateCallback: (accountId, id, callback) =>
    axios.patch(`${base(accountId)}/callbacks/${Number(id)}`, { callback }),
  routingRules: accountId => axios.get(`${base(accountId)}/routing_rules`),
  saveRoutingRule: (accountId, routingRule, id) =>
    id
      ? axios.patch(`${base(accountId)}/routing_rules/${Number(id)}`, {
          routing_rule: routingRule,
        })
      : axios.post(`${base(accountId)}/routing_rules`, {
          routing_rule: routingRule,
        }),
  reportSummary: (accountId, params = {}) =>
    axios.get(`${base(accountId)}/reports/summary`, { params }),
  integrationCapabilities: accountId =>
    axios.get(`${base(accountId)}/integrations/capabilities`),
};
