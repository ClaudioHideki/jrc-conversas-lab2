require 'rails_helper'

RSpec.describe JrcCampaigns::EligibilityPolicy do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:phone) { '+5511999990001' }
  let(:policy) { described_class.new(account: account, phone_number: phone) }

  it 'allows a list destination without creating positive consent records' do
    expect { expect(policy.list_rejection_reason).to be_nil }.not_to change(JrcCampaigns::Consent, :count)
    expect(policy.rejection_reason).to be_nil
  end

  it 'preserves a recorded withdrawal even after importing the number again' do
    JrcCampaigns::Consent.create!(account: account, recorded_by: admin, phone_number: phone, evidence: 'Historical',
                                 granted_at: 2.days.ago, revoked_at: 1.day.ago)
    expect(policy.list_rejection_reason).to match(/revogad/)
    expect(policy.rejection_reason).to match(/revogad/)
  end

  it 'accepts a subsequent active consent without deleting the withdrawal history' do
    JrcCampaigns::Consent.create!(account: account, recorded_by: admin, phone_number: phone, evidence: 'Historical',
                                 granted_at: 2.days.ago, revoked_at: 1.day.ago)
    JrcCampaigns::Consent.create!(account: account, recorded_by: admin, phone_number: phone, evidence: 'New permission', granted_at: Time.current)
    expect(policy.list_rejection_reason).to be_nil
  end

  it 'does not use another account permission to override this account withdrawal' do
    JrcCampaigns::Consent.create!(account: account, recorded_by: admin, phone_number: phone, evidence: 'Historical',
                                 granted_at: 2.days.ago, revoked_at: 1.day.ago)
    other = create(:account)
    JrcCampaigns::Consent.create!(account: other, recorded_by: admin, phone_number: phone, evidence: 'Other account', granted_at: Time.current)
    expect(policy.list_rejection_reason).to match(/revogad/)
  end

  it 'keeps blacklist and blocked contacts ineligible' do
    account.jrc_campaign_blacklists.create!(phone_number: phone, reason: 'Opt out')
    expect(policy.list_rejection_reason).to eq('Destinatário na blacklist.')
  end

  it 'lets the operator select the list before choosing the sender without granting consent' do
    create(:contact, account: account, phone_number: phone)
    campaign = JrcCampaigns::Campaign.new(account: account, created_by: admin, name: 'List preview')
    expect(JrcCampaigns::AudienceResolver.new(campaign).entries.map(&:phone_number)).to include(phone)
    expect(JrcCampaigns::Consent.where(account: account)).to be_empty
  end

  it 'keeps a blocked contact ineligible even without a separate consent record' do
    create(:contact, account: account, phone_number: phone, blocked: true)
    expect(policy.list_rejection_reason).to eq('Contato bloqueado.')
  end

  it 'does not treat an unrelated API inbox as a configured QR campaign connector' do
    create(:contact, account: account, phone_number: phone)
    inbox = create(:inbox, account: account, channel: create(:channel_api, account: account))
    campaign = JrcCampaigns::Campaign.create!(account: account, inbox: inbox, created_by: admin, name: 'Unconfigured inbox')
    expect(JrcCampaigns::AudienceResolver.new(campaign).entries).to be_empty
  end
end
