/* global axios */

const base = accountId => {
  const value = String(accountId);
  if (
    !/^[1-9]\d*$/.test(value) ||
    /[^0-9]/.test(value) ||
    !Number.isSafeInteger(Number(value))
  ) {
    throw new Error('Invalid account context');
  }
  return `/api/v1/accounts/${value}/jrc_contact_center`;
};

const recordIdentity = id => {
  const value = String(id);
  if (typeof id === 'number' && !Number.isSafeInteger(id))
    throw new Error('Invalid local record identity');
  if (
    !/^[1-9]\d{0,18}$/.test(value) ||
    /[^0-9]/.test(value) ||
    (value.length === 19 && value > '9223372036854775807')
  )
    throw new Error('Invalid local record identity');
  return value;
};
const ivrPath = (accountId, id) =>
  `${base(accountId)}/ivr_drafts/${recordIdentity(id)}`;
const audioInspectionPath = (accountId, assetId, versionId) =>
  `${base(accountId)}/audio_assets/${recordIdentity(assetId)}/versions/${recordIdentity(versionId)}/inspections`;
const ivrRevision = revision => {
  if (!Number.isInteger(revision) || revision < 1 || revision > 2147483647)
    throw new Error('Invalid local IVR revision');
  return revision;
};

const calendarIdentity = value => {
  if (
    typeof value !== 'string' ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(
      value
    )
  )
    throw new Error('Invalid local calendar identity');
  return value;
};

export default {
  manualEndingActions: (accountId, qualificationId, page = 1) =>
    axios.get(
      `${base(accountId)}/qualifications/${recordIdentity(qualificationId)}/ending_destinations`,
      { params: { page } }
    ),
  requestEndingDestination: (accountId, qualificationId, input) =>
    axios.post(
      `${base(accountId)}/qualifications/${recordIdentity(qualificationId)}/ending_destinations`,
      input
    ),
  retryEndingDestination: (accountId, qualificationId, attemptId, input) =>
    axios.post(
      `${base(accountId)}/qualifications/${recordIdentity(qualificationId)}/ending_destinations/${recordIdentity(attemptId)}/retry`,
      input
    ),
  resumeEndingDestination: (accountId, qualificationId, attemptId, review) =>
    axios.post(
      `${base(accountId)}/qualifications/${recordIdentity(qualificationId)}/ending_destinations/${recordIdentity(attemptId)}/resume`,
      { review }
    ),
  endingAttemptHistory: (accountId, qualificationId, params = {}) =>
    axios.get(
      `${base(accountId)}/qualifications/${recordIdentity(qualificationId)}/ending_attempts`,
      {
        params: {
          page: params.page || 1,
          ...(params.history_contract === 2 ? { history_contract: 2 } : {}),
        },
      }
    ),
  runPendingEndingAttempt: (accountId, qualificationId, attemptId, review) =>
    axios.post(
      `${base(accountId)}/qualifications/${recordIdentity(qualificationId)}/ending_attempts/${recordIdentity(attemptId)}/reprocess`,
      review
    ),
  queueCalendars: (accountId, unitId, calendarId, params = {}) =>
    axios.get(`${base(accountId)}/queue_calendars`, {
      params: {
        ...params,
        unit_id: recordIdentity(unitId),
        calendar_id: calendarIdentity(calendarId),
      },
    }),
  queueCalendar: (accountId, unitId, queueId) =>
    axios.get(`${base(accountId)}/queue_calendars/${recordIdentity(queueId)}`, {
      params: { unit_id: recordIdentity(unitId) },
    }),
  saveQueueCalendar: (accountId, queueId, body) =>
    axios.patch(
      `${base(accountId)}/queue_calendars/${recordIdentity(queueId)}`,
      body
    ),
  removeQueueCalendar: (accountId, queueId, body) =>
    axios.delete(
      `${base(accountId)}/queue_calendars/${recordIdentity(queueId)}`,
      { data: body }
    ),
  unitCalendars: (accountId, unitId, params = {}) =>
    axios.get(`${base(accountId)}/unit_calendars`, {
      params: { ...params, unit_id: recordIdentity(unitId) },
    }),
  unitCalendar: (accountId, unitId, id) =>
    axios.get(`${base(accountId)}/unit_calendars/${calendarIdentity(id)}`, {
      params: { unit_id: recordIdentity(unitId) },
    }),
  calendarIvrUsages: (accountId, unitId, id, params = {}) =>
    axios.get(
      `${base(accountId)}/unit_calendars/${calendarIdentity(id)}/ivr_usages`,
      {
        params: { ...params, unit_id: recordIdentity(unitId) },
      }
    ),
  saveUnitCalendar: (
    accountId,
    unitId,
    calendar,
    revision,
    existing = false
  ) => {
    const path = `${base(accountId)}/unit_calendars`;
    const id = calendarIdentity(calendar.id);
    const data = {
      unit_id: recordIdentity(unitId),
      calendar,
      expected_revision: revision,
    };
    return existing
      ? axios.patch(`${path}/${id}`, data)
      : axios.post(path, data);
  },
  previewUnitCalendar: (accountId, unitId, id, date) =>
    axios.get(
      `${base(accountId)}/unit_calendars/${calendarIdentity(id)}/preview`,
      { params: { unit_id: recordIdentity(unitId), date } }
    ),
  teamSupervisionCandidates: (accountId, teamId, params = {}) =>
    axios.get(
      `${base(accountId)}/team_supervisions/${recordIdentity(teamId)}/candidates`,
      { params }
    ),
  saveTeamSupervision: (accountId, teamId, supervision, options = {}) =>
    axios.patch(
      `${base(accountId)}/team_supervisions/${recordIdentity(teamId)}`,
      { supervision, expected_revision: options.expected_revision }
    ),
  moveAudioAssets: (accountId, body) =>
    axios.post(`${base(accountId)}/audio_asset_moves`, body),
  audioArchive: (accountId, items) =>
    axios.post(
      `${base(accountId)}/audio_archives`,
      { items },
      { responseType: 'blob', timeout: 30000 }
    ),
  audioBytes: (accountId, assetId, versionId) =>
    axios.get(
      `${base(accountId)}/audio_assets/${recordIdentity(assetId)}/versions/${recordIdentity(versionId)}/bytes`,
      { responseType: 'blob', timeout: 30000 }
    ),
  audioInspections: (accountId, assetId, versionId, params = {}) =>
    axios.get(audioInspectionPath(accountId, assetId, versionId), { params }),
  inspectAudioVersion: (accountId, assetId, versionId, idempotencyKey) =>
    axios.post(audioInspectionPath(accountId, assetId, versionId), {
      idempotency_key: idempotencyKey,
    }),
  audioAssets: (accountId, params = {}) =>
    axios.get(`${base(accountId)}/audio_assets`, { params }),
  audioAsset: (accountId, id) =>
    axios.get(`${base(accountId)}/audio_assets/${recordIdentity(id)}`),
  audioUsages: (accountId, id, params = {}) =>
    axios.get(`${base(accountId)}/audio_assets/${recordIdentity(id)}/usages`, {
      params,
    }),
  duplicateAudioAsset: (accountId, id, body) =>
    axios.post(
      `${base(accountId)}/audio_assets/${recordIdentity(id)}/duplicate`,
      body
    ),
  receiveAudioAsset: (accountId, body) =>
    axios.post(`${base(accountId)}/audio_assets`, body),
  updateAudioAsset: (accountId, id, asset, options = {}) =>
    axios.patch(`${base(accountId)}/audio_assets/${recordIdentity(id)}`, {
      asset,
      ...options,
    }),
  audioVersions: (accountId, id, params = {}) =>
    axios.get(
      `${base(accountId)}/audio_assets/${recordIdentity(id)}/versions`,
      {
        params,
      }
    ),
  audioVersion: (accountId, assetId, versionId) =>
    axios.get(
      `${base(accountId)}/audio_assets/${recordIdentity(assetId)}/versions/${recordIdentity(versionId)}`
    ),
  receiveAudioVersion: (accountId, id, body) =>
    axios.post(
      `${base(accountId)}/audio_assets/${recordIdentity(id)}/versions`,
      body
    ),
  audioFolders: (accountId, params = {}) =>
    axios.get(`${base(accountId)}/audio_folders`, { params }),
  audioFolder: (accountId, id) =>
    axios.get(`${base(accountId)}/audio_folders/${recordIdentity(id)}`),
  saveAudioFolder: (accountId, id, folder, options = {}) =>
    id !== undefined && id !== null
      ? axios.patch(`${base(accountId)}/audio_folders/${recordIdentity(id)}`, {
          folder,
          ...options,
        })
      : axios.post(`${base(accountId)}/audio_folders`, { folder }),
  acwForms: (accountId, params = {}) =>
    axios.get(`${base(accountId)}/acw_forms`, { params }),
  saveAcwForm: (accountId, id, form) =>
    id
      ? axios.patch(`${base(accountId)}/acw_forms/${recordIdentity(id)}`, {
          acw_form: form,
        })
      : axios.post(`${base(accountId)}/acw_forms`, { acw_form: form }),
  acwFormHistory: (accountId, id, page = 1) =>
    axios.get(`${base(accountId)}/acw_forms/${recordIdentity(id)}/versions`, {
      params: { page },
    }),
  acwFormVersion: (accountId, id, revision) =>
    axios.get(
      `${base(accountId)}/acw_forms/${recordIdentity(id)}/versions/${ivrRevision(revision)}`
    ),
  ivrReference: (accountId, resource, id) => {
    if (!['units', 'queues'].includes(resource))
      throw new Error('Invalid IVR reference type');
    return axios.get(`${base(accountId)}/${resource}/${recordIdentity(id)}`);
  },
  ivrDrafts: (accountId, params = {}) =>
    axios.get(`${base(accountId)}/ivr_drafts`, { params }),
  saveIvrDraft: (accountId, id, draft) =>
    id
      ? axios.patch(ivrPath(accountId, id), { ivr_draft: draft })
      : axios.post(`${base(accountId)}/ivr_drafts`, { ivr_draft: draft }),
  ivrHistory: (accountId, id, page = 1) =>
    axios.get(`${ivrPath(accountId, id)}/versions`, { params: { page } }),
  ivrVersion: (accountId, id, revision) =>
    axios.get(`${ivrPath(accountId, id)}/versions/${ivrRevision(revision)}`),
  exportIvrDraft: (accountId, id, revision) =>
    axios.get(`${ivrPath(accountId, id)}/export`, {
      params: { revision: ivrRevision(revision) },
      responseType: 'blob',
    }),
  previewIvrDraft: (accountId, preview) =>
    axios.post(`${base(accountId)}/ivr_drafts/preview`, {
      ivr_preview: preview,
    }),
  simulateIvrDraft: (accountId, id, revision, dtmf) =>
    axios.post(`${ivrPath(accountId, id)}/simulate`, {
      ivr_simulation: { revision: ivrRevision(revision), dtmf },
    }),
  configurationRecord: (accountId, resource, id) => {
    const paths = {
      units: 'units',
      queues: 'queues',
      memberships: 'queue_memberships',
      access_users: 'access_authorizations/users',
      access_teams: 'access_authorizations/teams',
      team_supervisions: 'team_supervisions',
      ivr_drafts: 'ivr_drafts',
      acw_forms: 'acw_forms',
      routing_rules: 'routing_rules',
      audio_folders: 'audio_folders',
      audio_assets: 'audio_assets',
    };
    if (!paths[resource] || !/^[1-9]\d*$/.test(String(id)))
      throw new Error('Invalid configuration context');
    if (resource === 'ivr_drafts') return axios.get(ivrPath(accountId, id));
    if (resource === 'team_supervisions')
      return axios.get(
        `${base(accountId)}/team_supervisions/${recordIdentity(id)}`
      );
    if (resource === 'audio_folders')
      return axios.get(
        `${base(accountId)}/audio_folders/${recordIdentity(id)}`
      );
    if (resource === 'audio_assets')
      return axios.get(`${base(accountId)}/audio_assets/${recordIdentity(id)}`);
    if (resource === 'acw_forms')
      return axios.get(`${base(accountId)}/acw_forms/${recordIdentity(id)}`);
    if (resource === 'routing_rules')
      return axios.get(
        `${base(accountId)}/routing_rules/${recordIdentity(id)}`
      );
    return axios.get(`${base(accountId)}/${paths[resource]}/${Number(id)}`);
  },
  pauseCatalog: accountId => axios.get(`${base(accountId)}/pause_catalog`),
  requestDeferredPause: (accountId, values, approvalDigest) =>
    axios.post(`${base(accountId)}/deferred_pause_request`, {
      deferred_pause_request: values,
      ...(approvalDigest ? { expected_approval_digest: approvalDigest } : {}),
    }),
  previewPauseApproval: (accountId, values) =>
    axios.post(`${base(accountId)}/deferred_pause_request/preview`, {
      deferred_pause_request: values,
    }),
  applyApprovedPause: (accountId, requestId, stateVersion) =>
    axios.post(`${base(accountId)}/deferred_pause_request/apply`, {
      deferred_pause_request: {
        request_id: requestId,
        expected_state_version: stateVersion,
      },
    }),
  cancelDeferredPause: (accountId, requestId) =>
    axios.delete(`${base(accountId)}/deferred_pause_request`, {
      data: { request_id: requestId },
    }),
  updatePauseCatalog: (accountId, catalog, options = {}) =>
    axios.patch(`${base(accountId)}/pause_catalog`, {
      ...options,
      pause_catalog: catalog,
    }),
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
    const { managerConfirmation, ...revision } = options || {};
    return axios.patch(
      `${base(accountId)}/access_authorizations/${type}/${recordIdentity(id)}`,
      {
        ...revision,
        authorization,
        ...(managerConfirmation
          ? { manager_confirmation: managerConfirmation }
          : {}),
      }
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
  endingRules: (accountId, params = {}) =>
    axios.get(`${base(accountId)}/acw_policy/ending_rules`, { params }),
  endingRuleSourceContext: (accountId, queueId) =>
    axios.get(`${base(accountId)}/acw_policy/ending_rules/source_context`, {
      params: { queue_id: recordIdentity(queueId) },
    }),
  activateEndingRule: (accountId, ruleCode, expectedRevision, requestKey) =>
    axios.post(`${base(accountId)}/acw_policy/ending_rules/activate`, {
      rule_code: ruleCode,
      expected_revision: expectedRevision,
      request_key: requestKey,
    }),
  endingRuleReadiness: (accountId, ruleCode, expectedRevision) =>
    axios.get(`${base(accountId)}/acw_policy/ending_rules/readiness`, {
      params: { rule_code: ruleCode, expected_revision: expectedRevision },
    }),
  saveEndingRule: (accountId, rule, expectedRevision) =>
    axios.post(`${base(accountId)}/acw_policy/ending_rules`, {
      private_rule: rule,
      expected_revision: expectedRevision,
    }),
  updateAcwPolicy: (accountId, limits, options = {}) =>
    axios.patch(`${base(accountId)}/acw_policy`, { ...options, limits }),
  qualifications: (accountId, params) =>
    axios.get(`${base(accountId)}/qualifications`, { params }),
  qualificationFormContext: (accountId, id, reasonCode) =>
    axios.get(
      `${base(accountId)}/qualifications/${recordIdentity(id)}/form_context`,
      { params: { reason_code: reasonCode } }
    ),
  startQualification: (accountId, params) =>
    axios.post(`${base(accountId)}/qualifications`, params),
  confirmQualificationReason: (accountId, id, body) =>
    axios.post(
      `${base(accountId)}/qualifications/${recordIdentity(id)}/confirm_reason`,
      body
    ),
  saveQualificationDraft: (accountId, id, qualification, expectedRevision) =>
    axios.patch(
      `${base(accountId)}/qualifications/${recordIdentity(id)}/draft`,
      {
        qualification,
        expected_draft_revision: expectedRevision,
      }
    ),
  completeQualification: (accountId, id, qualification, options = {}) =>
    axios.patch(`${base(accountId)}/qualifications/${recordIdentity(id)}`, {
      ...options,
      qualification,
    }),
  agentState: accountId => axios.get(`${base(accountId)}/agent_state`),
  agentStateHistory: (accountId, params = {}) =>
    axios.get(`${base(accountId)}/agent_state_histories`, { params }),
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
  routingRules: (accountId, params = {}) =>
    axios.get(`${base(accountId)}/routing_rules`, { params }),
  saveRoutingRule: (accountId, routingRule, id, options = {}) =>
    id
      ? axios.patch(`${base(accountId)}/routing_rules/${recordIdentity(id)}`, {
          ...options,
          routing_rule: routingRule,
        })
      : axios.post(`${base(accountId)}/routing_rules`, {
          routing_rule: routingRule,
        }),
  recordings: (accountId, params = {}) =>
    axios.get(`${base(accountId)}/recordings`, { params }),
  recording: (accountId, id) =>
    axios.get(`${base(accountId)}/recordings/${id}`),
  recordingBytes: (accountId, id, action, signal) =>
    axios.get(`${base(accountId)}/recordings/${id}/${action}`, {
      responseType: 'blob',
      signal,
    }),
  recordingReproduction: (accountId, id, data) =>
    axios.post(`${base(accountId)}/recordings/${id}/reproduce`, data),
  reportSummary: (accountId, params = {}) =>
    axios.get(`${base(accountId)}/reports/summary`, { params }),
  integrationCapabilities: accountId =>
    axios.get(`${base(accountId)}/integrations/capabilities`),
};
