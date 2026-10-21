export const sourceInboxesForChannel = (metadata, isEmail) => {
  const channelType = isEmail ? 'Channel::Email' : 'Channel::Whatsapp';
  const evolutionIds = new Set(
    (metadata.whatsapp_inboxes || [])
      .filter(inbox => inbox.connector === 'evolution')
      .map(inbox => Number(inbox.id))
  );
  return (metadata.source_inboxes || []).filter(
    inbox =>
      inbox.channel_type === channelType ||
      (!isEmail && evolutionIds.has(Number(inbox.id)))
  );
};

export const evolutionMinimumInterval = inboxes =>
  Math.max(
    0,
    ...inboxes
      .filter(inbox => inbox.connector === 'evolution')
      .map(inbox => Number(inbox.min_interval_seconds))
  );

export const testResultAlert = data => {
  if (!data.test_delivery_id) return 'JRC_CAMPAIGNS.ALERTS.TEST_SENT';
  return data.status === 'sent'
    ? 'JRC_CAMPAIGNS.EVOLUTION.TEST_ACCEPTED'
    : 'JRC_CAMPAIGNS.EVOLUTION.TEST_UNCONFIRMED';
};
