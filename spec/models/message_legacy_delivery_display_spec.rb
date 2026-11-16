require 'rails_helper'

RSpec.describe Message do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) do
    row = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing)
    row.update!(content_attributes: { 'retained' => 'synthetic' })
    obligation = JrcBrokerWebhookObligation.find_by!(message_id: row.id)
    obligation.update!(payload: obligation.payload.merge('content_attributes' => row.content_attributes))
    row
  end

  before do
    JrcBrokerIntegration.create!(account: account, broker_origin: 'https://broker.example.test', organization_id: SecureRandom.uuid,
                                 destination_revision: 1, encrypted_control_key: 'synthetic-not-used')
    JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid)
  end

  it 'projects unconfirmed legacy delivery for websocket reads without minting intent or mutating callback, message or jobs' do
    attributes = message.content_attributes.deep_dup
    obligation = JrcBrokerWebhookObligation.find_by!(message_id: message.id)
    payload = obligation.payload.deep_dup
    clear_enqueued_jobs
    data = message.push_event_data
    expect(data.dig(:content_attributes, 'jrc_broker_legacy_unconfirmed')).to be(true)
    expect(data[:content_attributes]).not_to have_key('jrc_broker_outbound')
    expect(message.reload.content_attributes).to eq(attributes)
    expect(obligation.reload.payload).to eq(payload)
    expect(enqueued_jobs).to be_empty
  end

  it 'keeps display-only evidence out of both webhook serializers' do
    expect(message.webhook_data[:content_attributes]).to eq('retained' => 'synthetic')
    expect(message.webhook_push_event_data[:content_attributes]).to eq('retained' => 'synthetic')
    expect(message.webhook_data.to_json).not_to include('jrc_broker_legacy_unconfirmed')
    expect(message.webhook_push_event_data.to_json).not_to include('jrc_broker_legacy_unconfirmed')
  end

  it 'preserves a generic API message without a durable Broker obligation' do
    generic = create(:message, account: account, inbox: create(:channel_api, account: account).inbox, message_type: :outgoing)
    expect(generic.push_event_data[:content_attributes]).not_to have_key('jrc_broker_legacy_unconfirmed')
  end

  it 'does not trust a client-supplied display flag on a generic message' do
    generic = create(:message, account: account, inbox: create(:channel_api, account: account).inbox, message_type: :outgoing,
                               content_attributes: { 'jrc_broker_legacy_unconfirmed' => true })
    expect(generic.push_event_data[:content_attributes]).not_to have_key('jrc_broker_legacy_unconfirmed')
    expect(generic.reload.content_attributes['jrc_broker_legacy_unconfirmed']).to be(true)
  end

  [{ 'jrc_broker_historical' => true }, { 'jrc_broker_message_id' => 'synthetic-observed', 'external_echo' => true }].each do |attributes|
    it "does not relabel independently observed or historical delivery #{attributes.keys.first}" do
      message.update!(content_attributes: attributes)
      expect(message.push_event_data[:content_attributes]).not_to have_key('jrc_broker_legacy_unconfirmed')
    end
  end

  it 'preserves an existing read acknowledgement' do
    message.update!(status: :read)
    expect(message.push_event_data[:content_attributes]).not_to have_key('jrc_broker_legacy_unconfirmed')
  end

  [nil, { 'version' => 1, 'outcome' => 'rejected', 'accepted' => false, 'uncertain' => false }].each do |diagnostic|
    it "projects a legacy failure read-only without inventing confirmation, including rejection proof #{diagnostic.present?}" do
      message.update!(status: :failed, content_attributes: { 'jrc_broker_delivery' => diagnostic })
      original = message.reload.content_attributes.deep_dup
      obligation = JrcBrokerWebhookObligation.find_by!(message_id: message.id)
      payload = obligation.payload.deep_dup
      rendered = message.push_event_data
      expect(rendered.dig(:content_attributes, 'jrc_broker_legacy_unconfirmed')).to be(true)
      expect(rendered.dig(:content_attributes, 'jrc_broker_delivery')).to eq(diagnostic)
      expect(rendered[:content_attributes]).not_to have_key('jrc_broker_outbound')
      expect(message.reload).to be_failed
      expect(message.content_attributes).to eq(original)
      expect(obligation.reload.payload).to eq(payload)
    end
  end

  it 'loads only one bounded obligation query for a paginated message list' do
    rows = [message]
    2.times do
      row = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing)
      row.update!(content_attributes: {})
      rows << row
    end
    queries = []
    data = nil
    ActiveSupport::Notifications.subscribed(lambda { |_name, _start, _finish, _id, payload|
      queries << payload[:sql] if payload[:sql].include?('FROM "jrc_broker_webhook_obligations"')
    }, 'sql.active_record') do
      data = MessageFinder.new(conversation, {}).perform.map(&:push_event_data)
    end
    expect(data.select { |row| rows.map(&:id).include?(row[:id]) }.map { |row| row.dig(:content_attributes, 'jrc_broker_legacy_unconfirmed') })
      .to eq([true, true, true])
    expect(queries.size).to eq(1)
    expect(queries.first).not_to include('"jrc_broker_webhook_obligations".*')
  end
end
