import { acwLabels } from '../inbox/acwLabels';

export const acwRulesSummary = (rows, t) => {
  if (!Array.isArray(rows) || rows.length === 0) return '—';
  const reasons = acwLabels(t).reasons;
  const scopes = {
    general: t('JRC_CONTACT_CENTER.ACW_RULES.GENERAL'),
    team: t('JRC_CONTACT_CENTER.ACW_RULES.TEAM'),
    queue: t('JRC_CONTACT_CENTER.ACW_RULES.QUEUE'),
  };
  return rows
    .map(row =>
      [
        `${t('JRC_CONTACT_CENTER.ACW_RULES.REASON')}: ${reasons[row.reason_code] || row.reason_code}`,
        `${scopes[row.scope]}${row.scope_id ? ` #${row.scope_id}` : ''}`,
        t('JRC_CONTACT_CENTER.ACW_RULES.EXACT_SECONDS', {
          seconds: row.limit_seconds,
        }),
        row.active
          ? t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.YES')
          : t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.NO'),
      ].join(' · ')
    )
    .join('\n');
};

export const acwFormBindingsSummary = (rows, t) => {
  if (!Array.isArray(rows) || rows.length === 0) return '—';
  return rows
    .map(row =>
      [
        t('JRC_CONTACT_CENTER.ACW_FORMS.PINNED_VERSION', {
          id: row.form_id,
          version: row.revision,
        }),
        t('JRC_CONTACT_CENTER.ACW_FORMS.RULE_REFERENCE', { id: row.rule_id }),
        t('JRC_CONTACT_CENTER.ACW_FORMS.REQUIRED_COUNT', {
          count: Array.isArray(row.required_fields)
            ? row.required_fields.length
            : 0,
        }),
      ].join(' · ')
    )
    .join('\n');
};
