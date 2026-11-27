require 'rails_helper'

RSpec.describe 'Meta status batches' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:inbox) do
    create(:inbox, account: account,
                   channel: create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false))
  end

  it 'processes every status and preserves normal conversation status updates' do
    first = JrcCampaigns::TestDelivery.create!(account: account, inbox: inbox, requested_by: user, idempotency_key: SecureRandom.uuid,
                                               phone_number: '+5511999990001', payload_digest: 'one', external_id: 'wamid.one', status: 'accepted')
    second = JrcCampaigns::TestDelivery.create!(account: account, inbox: inbox, requested_by: user, idempotency_key: SecureRandom.uuid,
                                                phone_number: '+5511999990002', payload_digest: 'two', external_id: 'wamid.two', status: 'accepted')
    conversation = create(:conversation, account: account, inbox: inbox)
    message = create(:message, account: account, inbox: inbox, conversation: conversation, source_id: 'wamid.normal', message_type: 'outgoing')
    statuses = [{ id: 'wamid.one', status: 'delivered' },
                { id: 'wamid.two', status: 'failed', errors: [{ code: 131_049, title: 'Provider restriction' }] }, { id: 'wamid.normal', status: 'read' }]
    service = Whatsapp::IncomingMessageBaseService.new(inbox: inbox, params: {})
    service.instance_variable_set(:@processed_params, { statuses: statuses })
    service.send(:process_statuses)
    expect(first.reload.status).to eq('delivered')
    expect(second.reload).to have_attributes(status: 'failed', error_code: '131049')
    expect(message.reload).to be_read
  end
end
