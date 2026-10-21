export const acwLabels = t => ({
  channels: {
    voice: t('JRC_CONTACT_CENTER.ACW_OPERATION.CHANNELS.voice'),
    whatsapp: t('JRC_CONTACT_CENTER.ACW_OPERATION.CHANNELS.whatsapp'),
  },
  reasons: {
    resolved: t('JRC_CONTACT_CENTER.ACW_OPERATION.REASONS.resolved'),
    information: t('JRC_CONTACT_CENTER.ACW_OPERATION.REASONS.information'),
    order: t('JRC_CONTACT_CENTER.ACW_OPERATION.REASONS.order'),
    callback: t('JRC_CONTACT_CENTER.ACW_OPERATION.REASONS.callback'),
    transfer: t('JRC_CONTACT_CENTER.ACW_OPERATION.REASONS.transfer'),
  },
  results: {
    completed: t('JRC_CONTACT_CENTER.ACW_OPERATION.RESULTS.completed'),
    pending: t('JRC_CONTACT_CENTER.ACW_OPERATION.RESULTS.pending'),
    callback: t('JRC_CONTACT_CENTER.ACW_OPERATION.RESULTS.callback'),
    forwarded: t('JRC_CONTACT_CENTER.ACW_OPERATION.RESULTS.forwarded'),
  },
});
