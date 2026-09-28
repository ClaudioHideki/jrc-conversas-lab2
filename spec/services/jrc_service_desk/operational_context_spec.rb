# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk::OperationalContext do
  include_context 'JRC Service Desk domain'

  it 'requires an active explicit unit grant' do
    expect(described_class.new(sd_context).unit_scope).to contain_exactly(sd_unit)
    sd_membership.update!(active: false)
    expect(described_class.new(sd_context).unit_scope).to be_empty
  end

  it 'does not infer units from TeamMember' do
    team = create(:team, account: sd_account)
    create(:team_member, team: team, user: sd_user)
    create(:jrc_sd_queue, unit: sd_other_unit, team: team)
    expect(described_class.new(sd_context).unit_scope).not_to include(sd_other_unit)
  end

  it 'does not bypass grants for administrator' do
    sd_as_admin!
    expect(described_class.new(sd_context).unit_scope).not_to include(sd_other_unit)
  end

  it 'refreshes a feature flag changed in the database while the input object is stale' do
    Account.find(sd_account.id).disable_features!('jrc_service_desk')
    expect(described_class.new(sd_context).available?).to be(false)
  end

  it 'rejects AccountUser from another Account' do
    foreign = create(:account_user, account: sd_foreign_account, user: sd_user)
    expect(described_class.new(sd_context.merge(account_user: foreign)).available?).to be(false)
  end

  it 'rejects manipulated hashes in place of native identity records' do
    expect(described_class.new(account: { id: sd_account.id }, user: sd_user, account_user: sd_account_user).available?).to be(false)
  end

  it 'rejects a different user with the current AccountUser' do
    expect(described_class.new(sd_context.merge(user: create(:user))).available?).to be(false)
  end

  it 'denies inactive units and inactive operators' do
    sd_unit.update!(active: false)
    expect(described_class.new(sd_context).unit_scope).to be_empty
    sd_unit.update!(active: true)
    sd_operator.update!(active: false)
    expect(described_class.new(sd_context).unit_scope).to be_empty
  end

  it 'does not borrow an existing custom role permission from CRM or Conversations' do
    role = create(:custom_role, account: sd_account, permissions: ['conversation_manage'])
    sd_account_user.update!(custom_role_id: role.id)
    expect(described_class.new(sd_context).native_operator?).to be(false)
  end
end
