require 'rails_helper'

RSpec.describe JrcCampaigns::OfficialTestService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_whatsapp, account: account) }
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:phone) { '+5511999990000' }
  let(:key) { SecureRandom.uuid }
  let(:renderer) { instance_double(JrcCampaigns::TemplateRenderer) }
  let(:step) { { 'kind' => 'template', 'template_name' => 'test', 'template_language' => 'pt_BR', 'template_params' => {} } }
  let(:service) do
    described_class.new(inbox: inbox, user: user, phone_number: phone, step: step, renderer: renderer, idempotency_key: key, operator_confirmed: true)
  end

  before do
    stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
    stub_request(:get, 'https://waba.360dialog.io/v1/configs/templates').to_return(status: 200, body: { waba_templates: [] }.to_json,
                                                                                   headers: { 'Content-Type' => 'application/json' })
    inbox
    channel.update!(message_templates: [{ 'name' => 'test', 'language' => 'pt_BR', 'status' => 'APPROVED',
                                          'components' => [{ 'type' => 'BODY', 'text' => 'Synthetic' }] }])
    allow(renderer).to receive(:render) { |value| value }
    JrcCampaigns::Consent.create!(account: account, phone_number: phone, granted_at: Time.current, evidence: 'Synthetic explicit consent',
                                  recorded_by: user, purpose: 'whatsapp_campaigns')
  end

  it 'persists provider acceptance and WAMID without claiming phone delivery' do
    expect(channel).to receive(:send_template).once.and_return('wamid.synthetic')
    first = service.perform
    second = service.perform
    expect(first[:status]).to eq('accepted')
    expect(first[:delivery_confirmed]).to be(false)
    expect(second[:test_delivery_id]).to eq(first[:test_delivery_id])
    expect(JrcCampaigns::TestDelivery.find(first[:test_delivery_id]).accepted_at).to be_present
  end

  it 'blocks unconfirmed sends and missing consent' do
    expect(channel).not_to receive(:send_template)
    unconfirmed = described_class.new(inbox: inbox, user: user, phone_number: phone, step: step, renderer: renderer, idempotency_key: key,
                                      operator_confirmed: false)
    expect { unconfirmed.perform }.to raise_error(ArgumentError, /Confirme/)
    JrcCampaigns::Consent.where(account: account).update_all(revoked_at: Time.current)
    expect { service.perform }.to raise_error(ArgumentError, /Consentimento/)
  end

  it 'does not resend after a timeout with an unknown outcome' do
    expect(channel).to receive(:send_template).once.and_raise(Net::ReadTimeout)
    expect(service.perform[:status]).to eq('unknown')
    expect(service.perform[:status]).to eq('unknown')
  end

  it 'rejects reuse of a key for another payload' do
    allow(channel).to receive(:send_template).and_return('wamid.synthetic')
    service.perform
    changed = described_class.new(inbox: inbox, user: user, phone_number: phone, step: step.merge('body' => 'different'), renderer: renderer,
                                  idempotency_key: key, operator_confirmed: true)
    expect { changed.perform }.to raise_error(ArgumentError, /outro teste/)
  end

  it 'recovers a delivery webhook arriving before the WAMID is persisted' do
    expect(channel).to receive(:send_template).once do
      JrcCampaigns::MetaStatusService.record(inbox: inbox, external_id: 'wamid.early', status: 'delivered', timestamp: Time.current.to_i.to_s)
      'wamid.early'
    end
    result = service.perform
    expect(result[:status]).to eq('delivered')
    expect(result[:delivery_confirmed]).to be(true)
    expect(JrcCampaigns::StatusEvent.sole.matched_at).to be_present
  end

  it 'handles duplicate and out-of-order statuses without regressing read receipts' do
    allow(channel).to receive(:send_template).and_return('wamid.sequence')
    result = service.perform
    %w[read read sent failed delivered].each do |status|
      JrcCampaigns::MetaStatusService.record(inbox: inbox, external_id: 'wamid.sequence', status: status, timestamp: '1795626000')
    end
    expect(JrcCampaigns::TestDelivery.find(result[:test_delivery_id]).status).to eq('read')
    expect(JrcCampaigns::StatusEvent.count).to eq(4)
  end

  it 'does not match a WAMID from another inbox' do
    allow(channel).to receive(:send_template).and_return('wamid.scoped')
    result = service.perform
    other = create(:inbox)
    JrcCampaigns::MetaStatusService.record(inbox: other, external_id: 'wamid.scoped', status: 'read')
    expect(JrcCampaigns::TestDelivery.find(result[:test_delivery_id]).status).to eq('accepted')
  end
end
