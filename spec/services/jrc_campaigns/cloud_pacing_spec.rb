require 'rails_helper'

RSpec.describe 'Cloud API campaign scheduling' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:provider) { 'whatsapp_cloud' }
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: provider, sync_templates: false, validate_provider_config: false).inbox
  end
  let(:contacts) { Array.new(3) { |index| create(:contact, account: account, phone_number: "+551199999000#{index}") } }
  let(:campaign) do
    account.jrc_campaigns.create!(name: 'Synthetic cloud schedule', created_by: admin, inbox: inbox,
                                  delay_min_seconds: 60, delay_max_seconds: 60,
                                  audience_config: { recipient_selection_mode: 'include', recipient_selection_keys: contacts.first(2).map do |contact|
                                    "contact:#{contact.id}"
                                  end },
                                  sending_window: { start: '00:00', end: '23:59', days: (0..6).to_a, timezone: 'UTC' })
  end

  around { |example| travel_to(Time.utc(2026, 11, 26, 15)) { example.run } }

  before do
    inbox.channel.update!(message_templates: [{ 'name' => 'approved', 'language' => 'pt_BR', 'status' => 'APPROVED', 'components' => [] }])
    campaign.steps.create!(kind: 'template', position: 0, template_name: 'approved', template_language: 'pt_BR')
    campaign.request_review!
    campaign.approve!(admin, campaign.review_digest)
  end

  it 'queues only the approved Cloud API recipients without the artificial recipient delay' do
    execution = JrcCampaigns::LaunchService.new(campaign).perform
    expect(execution.recipients.pluck(:contact_id)).to match_array(contacts.first(2).map(&:id))
    expect(execution.recipients.pluck(:scheduled_at)).to eq([Time.current, Time.current])
    expect(execution.recipients).to all(have_attributes(status: 'queued'))
    expect(WebMock).not_to have_requested(:post, /graph.facebook.com/)
  end

  it 'keeps pacing for a mixed official sender selection' do
    other = create(:channel_whatsapp, account: account, provider: 'default', sync_templates: false, validate_provider_config: false).inbox
    other.channel.update!(message_templates: inbox.channel.message_templates)
    campaign.campaign_inboxes.create!(inbox: inbox, enabled: true, position: 0)
    campaign.campaign_inboxes.create!(inbox: other, enabled: true, position: 1)
    campaign.request_review!
    campaign.approve!(admin, campaign.review_digest)
    execution = JrcCampaigns::LaunchService.new(campaign).perform
    expect(execution.recipients.order(:id).pluck(:scheduled_at)).to eq([1.minute.from_now, 2.minutes.from_now])
  end

  context 'with another official provider' do
    let(:provider) { 'default' }

    it 'preserves its configured delay instead of inheriting Cloud API pacing' do
      execution = JrcCampaigns::LaunchService.new(campaign).perform
      expect(execution.recipients.order(:id).pluck(:scheduled_at)).to eq([1.minute.from_now, 2.minutes.from_now])
    end
  end
end
