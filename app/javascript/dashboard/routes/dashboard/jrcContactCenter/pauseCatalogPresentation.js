// Presentation only: all authorization and catalog validation remain server-side.
export const pauseCatalogSummary = (entries, t) => {
  const minuteValue = value =>
    Number.isInteger(value)
      ? `${String(Math.floor(value / 60)).padStart(2, '0')}:${String(value % 60).padStart(2, '0')}`
      : '—';
  return entries
    .map(row =>
      [
        row.name,
        row.code,
        row.category,
        row.description,
        `${t('JRC_CONTACT_CENTER.ADMIN.ACTIVE')}: ${row.active ? t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.YES') : t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.NO')}`,
        `${t('JRC_CONTACT_CENTER.PAUSE_CATALOG.MINIMUM_MINUTES')}: ${minuteValue(row.minimum_minutes)}`,
        `${t('JRC_CONTACT_CENTER.PAUSE_CATALOG.DEFAULT_MINUTES')}: ${minuteValue(row.default_minutes)}`,
        `${t('JRC_CONTACT_CENTER.PAUSE_CATALOG.MAXIMUM_MINUTES')}: ${minuteValue(row.maximum_minutes)}`,
        `${t('JRC_CONTACT_CENTER.PAUSE_CATALOG.JUSTIFICATION_REQUIRED')}: ${row.justification_required === true ? t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.YES') : t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.NO')}`,
        `${t('JRC_CONTACT_CENTER.PAUSE_CATALOG.UNITS')}: ${row.unit_ids?.join(', ') || t('JRC_CONTACT_CENTER.PAUSE_CATALOG.INHERITED')}`,
        `${t('JRC_CONTACT_CENTER.PAUSE_CATALOG.PROFILES')}: ${row.custom_role_ids?.join(', ') || t('JRC_CONTACT_CENTER.PAUSE_CATALOG.INHERITED')}`,
      ]
        .filter(Boolean)
        .join('\n')
    )
    .join('\n\n');
};
