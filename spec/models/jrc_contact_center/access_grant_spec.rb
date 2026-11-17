require 'rails_helper'

RSpec.describe JrcContactCenter::AccessGrant do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:member) { account.account_users.find_by!(user: user) }
  let(:team) { create(:team, account: account) }

  it 'does not create eligibility merely by creating a platform user' do
    member
    expect(described_class.where(account: account, account_user: member)).to be_empty
    expect(described_class.new(account: account, account_user: member).eligible).to be(false)
  end

  it 'rejects unknown capabilities without persisting authority or audit changes' do
    grant = described_class.new(account: account, account_user: member, allowed: ['unregistered_admin'])
    expect(grant).not_to be_valid
    expect(grant.errors[:allowed]).not_to be_empty
  end

  it 'rejects a foreign user association at the model boundary' do
    foreign = create(:user, account: create(:account))
    grant = described_class.new(account: account, account_user: foreign.account_users.first)
    expect(grant).not_to be_valid
    expect(grant.errors[:account]).not_to be_empty
  end

  it 'enforces same-account membership even when model validation is bypassed' do
    foreign = create(:user, account: create(:account))
    grant = described_class.new(account: account, account_user: foreign.account_users.first)
    expect do
      described_class.transaction(requires_new: true) { grant.save!(validate: false) }
    end.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it 'enforces exactly one native subject in PostgreSQL' do
    grant = described_class.new(account: account, account_user: member, team: team)
    expect do
      described_class.transaction(requires_new: true) { grant.save!(validate: false) }
    end.to raise_error(ActiveRecord::StatementInvalid)
  end

  it 'prevents a team configuration from activating users or storing individual denials' do
    grant = described_class.new(account: account, team: team, eligible: true)
    expect(grant).not_to be_valid
    expect do
      described_class.transaction(requires_new: true) { grant.save!(validate: false) }
    end.to raise_error(ActiveRecord::StatementInvalid)
  end

  it 'removes team authority immediately on native team deletion while preserving its audit' do
    grant = described_class.create!(account: account, team: team, allowed: ['jrc_contact_center_publish'])
    audit_id = Audited.audit_class.where(auditable: grant).last.id
    team.destroy!
    expect(described_class.exists?(grant.id)).to be(false)
    expect(Audited.audit_class.exists?(audit_id)).to be(true)
  end
end
