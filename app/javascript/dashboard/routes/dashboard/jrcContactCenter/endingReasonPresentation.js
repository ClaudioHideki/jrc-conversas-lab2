export const endingReasonSummary = (catalog, t) => {
  const labels = {
    version: t('JRC_CONTACT_CENTER.ENDING_REASONS.VERSION'),
    code: t('JRC_CONTACT_CENTER.ENDING_REASONS.CODE'),
    name: t('JRC_CONTACT_CENTER.ENDING_REASONS.NAME'),
    category: t('JRC_CONTACT_CENTER.ENDING_REASONS.CATEGORY'),
    description: t('JRC_CONTACT_CENTER.ENDING_REASONS.DESCRIPTION'),
    order: t('JRC_CONTACT_CENTER.ENDING_REASONS.ORDER'),
    status: t('JRC_CONTACT_CENTER.ENDING_REASONS.STATUS'),
    active: t('JRC_CONTACT_CENTER.ENDING_REASONS.ACTIVE'),
    inactive: t('JRC_CONTACT_CENTER.ENDING_REASONS.INACTIVE'),
  };
  const header = `${labels.version} ${catalog.version}`;
  const queues = catalog.required_queue_ids?.length
    ? [
        `${t('JRC_CONTACT_CENTER.ENDING_REASONS.REQUIRED_QUEUES')}: ${catalog.required_queue_ids.map(id => `#${id}`).join(', ')}`,
      ]
    : [];
  const rows = catalog.entries.map(row =>
    [
      `${labels.code}: ${row.code}`,
      `${labels.name}: ${row.name}`,
      `${labels.category}: ${row.category}`,
      `${labels.description}: ${row.description || '—'}`,
      `${labels.order}: ${row.order}`,
      `${labels.status}: ${row.active ? labels.active : labels.inactive}`,
    ].join(' · ')
  );
  return [header, ...queues, ...rows].join('\n');
};
