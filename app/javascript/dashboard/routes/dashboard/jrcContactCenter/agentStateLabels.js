export const agentStateLabels = t => ({
  offline: t('JRC_CONTACT_CENTER.AGENT.STATES.offline'),
  available: t('JRC_CONTACT_CENTER.AGENT.STATES.available'),
  paused: t('JRC_CONTACT_CENTER.AGENT.STATES.paused'),
  busy: t('JRC_CONTACT_CENTER.AGENT.STATES.busy'),
  ringing: t('JRC_CONTACT_CENTER.AGENT.STATES.ringing'),
  in_call: t('JRC_CONTACT_CENTER.AGENT.STATES.in_call'),
  acw: t('JRC_CONTACT_CENTER.AGENT.STATES.acw'),
  unavailable: t('JRC_CONTACT_CENTER.AGENT.STATES.unavailable'),
});

export const pauseReasonLabels = t => ({
  bathroom: t('JRC_CONTACT_CENTER.AGENT.PAUSE_REASONS.bathroom'),
  coffee: t('JRC_CONTACT_CENTER.AGENT.PAUSE_REASONS.coffee'),
  lunch: t('JRC_CONTACT_CENTER.AGENT.PAUSE_REASONS.lunch'),
  meeting: t('JRC_CONTACT_CENTER.AGENT.PAUSE_REASONS.meeting'),
  training: t('JRC_CONTACT_CENTER.AGENT.PAUSE_REASONS.training'),
  feedback: t('JRC_CONTACT_CENTER.AGENT.PAUSE_REASONS.feedback'),
  backoffice: t('JRC_CONTACT_CENTER.AGENT.PAUSE_REASONS.backoffice'),
  internal_support: t(
    'JRC_CONTACT_CENTER.AGENT.PAUSE_REASONS.internal_support'
  ),
  technical_issue: t('JRC_CONTACT_CENTER.AGENT.PAUSE_REASONS.technical_issue'),
  rest: t('JRC_CONTACT_CENTER.AGENT.PAUSE_REASONS.rest'),
  end_shift: t('JRC_CONTACT_CENTER.AGENT.PAUSE_REASONS.end_shift'),
});
