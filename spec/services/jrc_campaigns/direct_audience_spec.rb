require 'rails_helper'

RSpec.describe 'Campaign audiences without prior consent registration' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:phone) { '+5511999990001' }
  let(:contact) { create(:contact, account: account, phone_number: phone) }
  let(:inbox) do
    create(:inbox, account: account,
                   channel: create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                                      validate_provider_config: false))
  end
  let(:campaign) { JrcCampaigns::Campaign.new(account: account, name: 'Synthetic direct audience', inbox: inbox) }

  it 'includes a selected official-channel contact without granting or importing consent' do
    contact
    expect { expect(JrcCampaigns::AudienceResolver.new(campaign).entries.map(&:phone_number)).to eq([phone]) }
      .not_to change(JrcCampaigns::Consent, :count)
    expect(JrcCampaigns::EligibilityPolicy.new(account: account, phone_number: phone).rejection_reason).to be_nil
  end

  it 'includes a sanitized number without granting consent or adding it to the account contacts' do
    list = account.jrc_campaign_sanitized_lists.create!(name: 'Synthetic CSV', created_by: admin)
    list.entries.create!(name: 'Synthetic number', phone_number: phone, normalized_phone: phone, status: 'valid')
    campaign.assign_attributes(audience_type: 'sanitized_list', audience_config: { sanitized_list_id: list.id })
    expect(JrcCampaigns::AudienceResolver.new(campaign).entries.map(&:phone_number)).to eq([phone])
    expect(account.contacts).to be_empty
    expect(JrcCampaigns::Consent.where(account: account)).to be_empty
  end

  it 'preserves a recorded withdrawal and all original evidence' do
    contact
    record = JrcCampaigns::Consent.create!(account: account, recorded_by: admin, phone_number: phone, evidence: 'Synthetic withdrawal',
                                           granted_at: 2.days.ago, revoked_at: 1.day.ago)
    original = record.attributes
    expect(JrcCampaigns::AudienceResolver.new(campaign).entries).to be_empty
    expect(JrcCampaigns::EligibilityPolicy.new(account: account, phone_number: phone).rejection_reason).to match(/revogad/)
    expect(record.reload.attributes).to eq(original)
  end

  it 'still excludes blacklist, blocked and foreign-account contacts' do
    contact.update!(blocked: true)
    create(:contact, phone_number: '+5511999990002')
    expect(JrcCampaigns::AudienceResolver.new(campaign).entries).to be_empty
    contact.update!(blocked: false)
    account.jrc_campaign_blacklists.create!(phone_number: phone, reason: 'Synthetic opt out')
    expect(JrcCampaigns::AudienceResolver.new(campaign).entries).to be_empty
  end

  it 'uses labels, inboxes and CRM stages without requiring consent registration' do
    label = create(:label, account: account)
    contact.add_labels([label.title])
    create(:contact_inbox, contact: contact, inbox: inbox)
    pipeline = create(:jrc_crm_pipeline, account: account)
    stage = create(:jrc_crm_stage, account: account, pipeline: pipeline)
    create(:jrc_crm_deal, account: account, pipeline: pipeline, stage: stage, owner: admin, contact: contact)
    {
      'label' => { label_ids: [label.id] },
      'inbox' => { inbox_ids: [inbox.id] },
      'crm_stage' => { stage_ids: [stage.id] }
    }.each do |source, config|
      campaign.assign_attributes(audience_type: source, audience_config: config)
      expect(JrcCampaigns::AudienceResolver.new(campaign).entries.map(&:phone_number)).to eq([phone])
    end
    expect(JrcCampaigns::Consent.where(account: account)).to be_empty
  end
end
