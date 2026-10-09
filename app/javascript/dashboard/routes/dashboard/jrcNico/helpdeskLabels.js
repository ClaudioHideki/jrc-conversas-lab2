export const buildHelpdeskLabels = t => {
  const groups = {
    catalog: {
      available_with_native_authorization: t(
        'JRC_NICO_HELPDESK.CATALOG_STATES.available_with_native_authorization'
      ),
      blocked_dependency: t(
        'JRC_NICO_HELPDESK.CATALOG_STATES.blocked_dependency'
      ),
    },
    states: {
      draft: t('JRC_NICO_HELPDESK.STATES.draft'),
      published: t('JRC_NICO_HELPDESK.STATES.published'),
      halted: t('JRC_NICO_HELPDESK.STATES.halted'),
      detected: t('JRC_NICO_HELPDESK.STATES.detected'),
      prepared: t('JRC_NICO_HELPDESK.STATES.prepared'),
      pending: t('JRC_NICO_HELPDESK.STATES.pending'),
      approved: t('JRC_NICO_HELPDESK.STATES.approved'),
      executing: t('JRC_NICO_HELPDESK.STATES.executing'),
      succeeded: t('JRC_NICO_HELPDESK.STATES.succeeded'),
      reconciled: t('JRC_NICO_HELPDESK.STATES.reconciled'),
      failed: t('JRC_NICO_HELPDESK.STATES.failed'),
      blocked: t('JRC_NICO_HELPDESK.STATES.blocked'),
      unknown: t('JRC_NICO_HELPDESK.STATES.unknown'),
      cancelled: t('JRC_NICO_HELPDESK.STATES.cancelled'),
    },
    rules: {
      R01: t('JRC_NICO_HELPDESK.RULE_NAMES.R01'),
      R02: t('JRC_NICO_HELPDESK.RULE_NAMES.R02'),
      R03: t('JRC_NICO_HELPDESK.RULE_NAMES.R03'),
      R04: t('JRC_NICO_HELPDESK.RULE_NAMES.R04'),
      R05: t('JRC_NICO_HELPDESK.RULE_NAMES.R05'),
      R06: t('JRC_NICO_HELPDESK.RULE_NAMES.R06'),
      R07: t('JRC_NICO_HELPDESK.RULE_NAMES.R07'),
      R08: t('JRC_NICO_HELPDESK.RULE_NAMES.R08'),
      R09: t('JRC_NICO_HELPDESK.RULE_NAMES.R09'),
      R10: t('JRC_NICO_HELPDESK.RULE_NAMES.R10'),
      R11: t('JRC_NICO_HELPDESK.RULE_NAMES.R11'),
      R12: t('JRC_NICO_HELPDESK.RULE_NAMES.R12'),
      R13: t('JRC_NICO_HELPDESK.RULE_NAMES.R13'),
      R14: t('JRC_NICO_HELPDESK.RULE_NAMES.R14'),
      R15: t('JRC_NICO_HELPDESK.RULE_NAMES.R15'),
      R16: t('JRC_NICO_HELPDESK.RULE_NAMES.R16'),
    },
    roles: {
      n2: t('JRC_NICO_HELPDESK.ROLES.n2'),
      thiago: t('JRC_NICO_HELPDESK.ROLES.thiago'),
      supervisor: t('JRC_NICO_HELPDESK.ROLES.supervisor'),
      cs: t('JRC_NICO_HELPDESK.ROLES.cs'),
      management: t('JRC_NICO_HELPDESK.ROLES.management'),
      director: t('JRC_NICO_HELPDESK.ROLES.director'),
      ceo: t('JRC_NICO_HELPDESK.ROLES.ceo'),
      legal: t('JRC_NICO_HELPDESK.ROLES.legal'),
    },
    channels: {
      nico: t('JRC_NICO_HELPDESK.CHANNELS.nico'),
      email: t('JRC_NICO_HELPDESK.CHANNELS.email'),
      whatsapp: t('JRC_NICO_HELPDESK.CHANNELS.whatsapp'),
    },
    conflicts: {
      R03: t('JRC_NICO_HELPDESK.CONFLICTS.R03'),
      R05: t('JRC_NICO_HELPDESK.CONFLICTS.R05'),
      R07: t('JRC_NICO_HELPDESK.CONFLICTS.R07'),
      R08: t('JRC_NICO_HELPDESK.CONFLICTS.R08'),
      R09: t('JRC_NICO_HELPDESK.CONFLICTS.R09'),
    },
    fields: {
      window_days: t('JRC_NICO_HELPDESK.FIELDS.window_days'),
      window_minutes: t('JRC_NICO_HELPDESK.FIELDS.window_minutes'),
      count: t('JRC_NICO_HELPDESK.FIELDS.count'),
      percent: t('JRC_NICO_HELPDESK.FIELDS.percent'),
      hours: t('JRC_NICO_HELPDESK.FIELDS.hours'),
      days: t('JRC_NICO_HELPDESK.FIELDS.days'),
    },
    kpiNames: {
      K1: t('JRC_NICO_HELPDESK.KPI_NAMES.K1'),
      K2: t('JRC_NICO_HELPDESK.KPI_NAMES.K2'),
      K3: t('JRC_NICO_HELPDESK.KPI_NAMES.K3'),
      K4: t('JRC_NICO_HELPDESK.KPI_NAMES.K4'),
      K5: t('JRC_NICO_HELPDESK.KPI_NAMES.K5'),
      K6: t('JRC_NICO_HELPDESK.KPI_NAMES.K6'),
      K7: t('JRC_NICO_HELPDESK.KPI_NAMES.K7'),
    },
    kpiFormulas: {
      K1: t('JRC_NICO_HELPDESK.KPI_FORMULAS.K1'),
      K2: t('JRC_NICO_HELPDESK.KPI_FORMULAS.K2'),
      K3: t('JRC_NICO_HELPDESK.KPI_FORMULAS.K3'),
      K4: t('JRC_NICO_HELPDESK.KPI_FORMULAS.K4'),
      K5: t('JRC_NICO_HELPDESK.KPI_FORMULAS.K5'),
      K6: t('JRC_NICO_HELPDESK.KPI_FORMULAS.K6'),
      K7: t('JRC_NICO_HELPDESK.KPI_FORMULAS.K7'),
    },
  };
  const noData = t('JRC_NICO_HELPDESK.NO_DATA');
  return (group, key) =>
    Object.hasOwn(groups[group], key) ? groups[group][key] : noData;
};
