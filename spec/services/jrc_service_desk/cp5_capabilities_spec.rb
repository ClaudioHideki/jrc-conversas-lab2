# frozen_string_literal: true
require 'rails_helper'

RSpec.describe JrcServiceDesk::OperationalContext do
  include_context 'JRC Service Desk domain'

  def native_custom_role(*keys, account: sd_account)
    skip 'Native CustomRole extension unavailable; no replacement RBAC' unless defined?(::CustomRole) && sd_account_user.respond_to?(:custom_role)
    role = CustomRole.create!(account: account, name: SecureRandom.hex(6), permissions: keys.map { |key| "jrc_service_desk_#{key}" })
    sd_account_user.update!(custom_role: role)
    role
  end

  it 'reads explicit native custom permissions, not the administrator bit' do
    sd_as_admin!
    native_custom_role('module_view', 'tickets_view')
    context = described_class.new(sd_context)
    expect(context.capability?(:tickets_view)).to be(true)
    expect(context.capability?(:tickets_edit)).to be(false)
    expect(context.capability?(:tickets_view_all)).to be(false)
    expect(context.capability?(:lifecycle_policies_manage)).to be(false)
  end

  it 'denies dangling or foreign native custom role references' do
    native_custom_role('module_view', 'tickets_view', account: sd_foreign_account)
    expect(described_class.new(sd_context).native_operator?).to be(false)
  end

  it 'observes native capability revocation on the next evaluation' do
    role = native_custom_role('module_view', 'tickets_view', 'tickets_edit')
    expect(described_class.new(sd_context).capability?(:tickets_edit)).to be(true)
    role.update!(permissions: [])
    expect(described_class.new(sd_context).native_operator?).to be(false)
  end

  it 'never grants access by role alone after the UnitMembership is revoked' do
    sd_as_admin!
    sd_membership.update!(active: false)
    expect(JrcServiceDesk::ModulePolicy.new(sd_context, :service_desk).show?).to be(false)
    expect(JrcServiceDesk::TicketPolicy::Scope.new(sd_context, JrcServiceDesk::Ticket).resolve).to be_empty
  end

  it 'denies all action capabilities with the flag disabled' do
    sd_as_admin!
    sd_account.disable_features!('jrc_service_desk')
    expect(described_class.new(sd_context).effective_capabilities).to eq([])
  end

  it 'does not use Team as UnitMembership' do
    team = create(:team, account: sd_account)
    create(:team_member, team: team, user: sd_user)
    row = create(:jrc_sd_ticket, unit: sd_other_unit, team: team)
    expect(JrcServiceDesk::TicketPolicy.new(sd_context, row).show?).to be(false)
  end
  it 'denies a mismatched native AccountUser or forged Account context' do
    foreign_user = create(:user)
    foreign_au = create(:account_user, account: sd_foreign_account, user: foreign_user, role: :administrator)
    forged = { account: sd_account, user: sd_user, account_user: foreign_au }
    expect(described_class.new(forged).effective_capabilities).to eq([])
    forged = { account: sd_foreign_account, user: sd_user, account_user: sd_account_user }
    expect(described_class.new(forged).native_operator?).to be(false)
  end

  it 'preserves native role deletion semantics without bypassing revoked unit access' do
    sd_as_admin!
    role = native_custom_role('module_view', 'tickets_view')
    sd_membership.update!(active: false)
    role.destroy!
    expect(sd_account_user.reload.custom_role_id).to be_nil
    expect(JrcServiceDesk::ModulePolicy.new(sd_context, :service_desk).show?).to be(false)
  end

end
