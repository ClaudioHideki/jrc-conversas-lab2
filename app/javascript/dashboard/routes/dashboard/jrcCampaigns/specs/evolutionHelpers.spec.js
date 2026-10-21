import {
  sourceInboxesForChannel,
  evolutionMinimumInterval,
  testResultAlert,
} from '../evolutionHelpers';

describe('Evolution campaign sender', () => {
  const metadata = {
    source_inboxes: [
      { id: 1, channel_type: 'Channel::Whatsapp' },
      { id: 8, channel_type: 'Channel::Api' },
      { id: 9, channel_type: 'Channel::Api' },
      { id: 10, channel_type: 'Channel::Email' },
    ],
    whatsapp_inboxes: [
      { id: 8, connector: 'evolution', min_interval_seconds: 60 },
    ],
  };

  it('includes only the configured API inbox alongside official WhatsApp', () => {
    expect(
      sourceInboxesForChannel(metadata, false).map(item => item.id)
    ).toEqual([1, 8]);
  });

  it('preserves the email source filter', () => {
    expect(
      sourceInboxesForChannel(metadata, true).map(item => item.id)
    ).toEqual([10]);
  });

  it('uses the server minimum interval for Evolution and leaves official senders alone', () => {
    expect(evolutionMinimumInterval(metadata.whatsapp_inboxes)).toBe(60);
    expect(evolutionMinimumInterval([{ id: 1 }])).toBe(0);
  });

  it('does not report an unknown test result as sent', () => {
    expect(
      testResultAlert({ test_delivery_id: 1, status: 'unknown' })
    ).toContain('TEST_UNCONFIRMED');
    expect(testResultAlert({ test_delivery_id: 1, status: 'sent' })).toContain(
      'TEST_ACCEPTED'
    );
    expect(testResultAlert({ message_id: 'official' })).toBe(
      'JRC_CAMPAIGNS.ALERTS.TEST_SENT'
    );
  });
});
