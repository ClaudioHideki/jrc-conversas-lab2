require 'rails_helper'

RSpec.describe JrcCampaigns::Sanitizer do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:entry) { { 'name' => 'Synthetic requester', 'phone' => '+5511999999000', 'contact_id' => 7, 'ticket_ids' => [11, 12] } }

  it 'preserves the exact source metadata required by a reviewed NICO incident receipt without mutating input' do
    original = entry.deep_dup
    list = described_class.new(account: account, user: user, name: 'Reviewed draft', entries: [entry],
                               include_channel_statuses: false).perform

    expect(list.entries.first.metadata).to eq('contact_id' => 7, 'ticket_ids' => [11, 12])
    expect(list.entries.first.normalized_phone).to eq('+5511999999000')
    expect(entry).to eq(original)
    expect(JrcCampaigns::Consent.where(account: account)).to be_empty
    expect(account.jrc_campaigns).to be_empty
  end

  it 'keeps GoPure channel classification by default and does not invent consent' do
    list = described_class.new(account: account, user: user, name: 'Campaign import', entries: [entry]).perform

    expect(list.entries.first.metadata).to eq(
      'contact_id' => 7, 'ticket_ids' => [11, 12], 'phone_status' => 'valid', 'email_status' => 'invalid'
    )
    expect(JrcCampaigns::Consent.where(account: account)).to be_empty
  end

  it 'keeps email-only lists compatible with the imported campaign sender' do
    list = described_class.new(account: account, user: user, name: 'Email import',
                               entries: [{ email: 'synthetic@example.test' }]).perform

    expect(list.entries.first).to have_attributes(normalized_email: 'synthetic@example.test', status: 'valid')
    expect(list.entries.first.metadata).to eq('phone_status' => 'invalid', 'email_status' => 'valid')
    expect(JrcCampaigns::Consent.where(account: account)).to be_empty
  end
end
