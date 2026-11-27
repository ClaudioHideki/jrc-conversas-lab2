require 'rails_helper'

RSpec.describe 'Campaign deletion and receipt reports', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).inbox
  end
  let(:campaign) { account.jrc_campaigns.create!(name: 'Synthetic', created_by: admin, status: 'completed') }
  let(:execution) { campaign.executions.create!(run_number: 1, status: 'completed') }
  let(:recipient) do
    execution.recipients.create!(campaign: campaign, inbox: inbox, phone_number: '+5511999990001', destination: '+5511999990001',
                                 status: 'sent', sent_at: 1.hour.ago)
  end
  let(:step) { campaign.steps.create!(kind: 'text', position: 0, body: 'Synthetic') }
  let(:delivery) { recipient.deliveries.create!(step: step, inbox: inbox, status: 'sent', external_id: 'wamid.synthetic', sent_at: 1.hour.ago) }
  let(:path) { "/api/v1/accounts/#{account.id}/jrc_campaigns/campaigns/#{campaign.id}" }

  before { account.enable_features!('jrc_campaigns') }

  it 'deletes completed campaigns and their reports without removing contacts or messages' do
    delivery
    contact = create(:contact, account: account)
    message = create(:message, account: account)
    delete path, headers: headers
    expect(response).to have_http_status(:no_content)
    expect(JrcCampaigns::Campaign.exists?(campaign.id)).to be(false)
    expect(JrcCampaigns::Recipient.exists?(recipient.id)).to be(false)
    expect(JrcCampaigns::Delivery.exists?(delivery.id)).to be(false)
    expect(Contact.exists?(contact.id)).to be(true)
    expect(Message.exists?(message.id)).to be(true)
  end

  %w[running paused].each do |state|
    it "rejects deletion of a #{state} campaign" do
      campaign.update!(status: state)
      delete path, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(campaign.reload.status).to eq(state)
    end
  end

  it 'rejects deletion by an agent' do
    agent = create(:user, account: account, role: :agent)
    delete path, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    expect(JrcCampaigns::Campaign.exists?(campaign.id)).to be(true)
  end

  it 'does not expose or delete another account campaign' do
    foreign = create(:account).jrc_campaigns.create!(name: 'Foreign')
    delete "/api/v1/accounts/#{account.id}/jrc_campaigns/campaigns/#{foreign.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(JrcCampaigns::Campaign.exists?(foreign.id)).to be(true)
  end

  it 'reflects official read callbacks even after completion and ignores a late delivered callback' do
    delivery
    %w[delivered read delivered].each do |state|
      service = Whatsapp::IncomingMessageBaseService.new(inbox: inbox, params: {})
      service.instance_variable_set(:@processed_params, { statuses: [{ id: delivery.external_id, status: state }] })
      service.send(:process_statuses)
    end
    get "#{path}/report", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['recipients'].first).to include('status' => 'read')
    expect(response.parsed_body['summary']).to include('delivered' => 1, 'read' => 1)
    expect(campaign.reload.status).to eq('completed')
    expect(campaign.read_count).to eq(1)
  end

  it 'preserves recipient read state when another step receives delivery confirmation' do
    delivery
    JrcCampaigns::StatusTrackerService.call(inbox: inbox, external_id: delivery.external_id, status: 'read')
    second_step = campaign.steps.create!(kind: 'text', position: 1, body: 'Second')
    second = recipient.deliveries.create!(step: second_step, inbox: inbox, status: 'sent', sent_at: Time.current, external_id: 'wamid.second')
    JrcCampaigns::StatusTrackerService.call(inbox: inbox, external_id: second.external_id, status: 'delivered')
    expect(recipient.reload).to be_read
    expect(recipient.read_at).to be_present
    expect(second.reload).to be_delivered
  end

  it 'does not match a read receipt from another inbox or account' do
    delivery
    other = create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).inbox
    expect(JrcCampaigns::MetaStatusService.record(inbox: other, external_id: delivery.external_id, status: 'read')).to be(false)
    expect(delivery.reload).to be_sent
    expect(recipient.reload.read_at).to be_nil
  end

  {
    '131049' => 'This message was not delivered to maintain healthy ecosystem engagement.',
    '131026' => 'Message undeliverable'
  }.each do |code, title|
    it "reports confirmed provider code #{code} without changing original evidence" do
      delivery
      JrcCampaigns::MetaStatusService.record(inbox: inbox, external_id: delivery.external_id, status: 'failed',
                                             errors: [{ code: code, title: title }])
      original = recipient.reload.attributes
      get "#{path}/report", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['recipients'].first).to include('error_code' => code, 'error_message' => title)
      expect(recipient.reload.attributes).to eq(original)
    end
  end

  it 'does not attribute an error code from a foreign inbox to this recipient' do
    delivery.update!(status: 'failed', error_message: 'Unknown error')
    recipient.update!(status: 'failed', error_message: 'Unknown error')
    other = create(:inbox)
    JrcCampaigns::StatusEvent.create!(inbox: other, external_id: delivery.external_id, status: 'failed', occurred_at: Time.current,
                                      fingerprint: SecureRandom.hex, provider_errors: [{ 'code' => '131049', 'title' => 'Foreign evidence' }])
    get "#{path}/report", headers: headers
    expect(response.parsed_body['recipients'].first).to include('error_code' => nil, 'error_message' => 'Unknown error')
  end

  it 'leaves delivery unconfirmed as read when no read callback is received' do
    delivery
    JrcCampaigns::MetaStatusService.record(inbox: inbox, external_id: delivery.external_id, status: 'delivered')
    get "#{path}/report", headers: headers
    expect(response.parsed_body['recipients'].first).to include('status' => 'delivered', 'read_at' => nil)
    expect(response.parsed_body['summary']['read']).to eq(0)
  end
end
