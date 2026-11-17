require 'rails_helper'

RSpec.describe JrcContactCenter::PermissionSources do
  let(:account) { create(:account) }
  let(:user) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: user) }
  let(:grant) { JrcContactCenter::AccessGrant.find_by!(account_user: member) }
  let(:role) { create(:custom_role, account: account, permissions: ['jrc_contact_center_view']) }
  let(:team) { create(:team, account: account) }
  let(:context) { { account: account, account_user: member, user: user } }
  let(:policy) { JrcContactCenter::ModulePolicy.new(context, :contact_center) }

  before do
    account.enable_features!('jrc_contact_center')
    member.update!(custom_role: role)
  end

  it 'denies every capability to a newly created native administrator without explicit eligibility' do
    pending = create(:user, account: account, role: :administrator)
    link = account.account_users.find_by!(user: pending)
    pending_policy = JrcContactCenter::ModulePolicy.new({ account: account, account_user: link, user: pending }, :contact_center)
    expect(pending_policy.effective_permissions).to eq([])
  end

  it 'keeps an ineligible user denied even with an explicit full profile and team grants' do
    role.update!(permissions: JrcContactCenter::ModulePolicy::PERMISSIONS)
    team.add_members([user.id])
    JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: JrcContactCenter::ModulePolicy::PERMISSIONS)
    grant.update!(eligible: false)
    expect(policy.effective_permissions).to eq([])
  end

  it 'inherits only actual memberships in a native team of the same account' do
    team.add_members([user.id])
    JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: ['jrc_contact_center_operate'])
    expect(policy.operate?).to be(true)
    expect(policy.publish?).to be(false)
  end

  it 'unions multiple native teams without inventing a supervisor or queue participation' do
    second = create(:team, account: account)
    [team, second].each { |item| item.add_members([user.id]) }
    JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: ['jrc_contact_center_recordings_view'])
    JrcContactCenter::AccessGrant.create!(account: account, team: second, allowed: ['jrc_contact_center_recordings_listen'])
    expect(policy.recordings_listen?).to be(true)
    expect(policy.recordings_download?).to be(false)
    expect(JrcContactCenter::QueueMembership.where(account_user: member)).to be_empty
  end

  it 'lets explicit individual denial override both a profile and a team' do
    role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_publish])
    team.add_members([user.id])
    JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: ['jrc_contact_center_publish'])
    grant.update!(allowed: ['jrc_contact_center_publish'], denied: ['jrc_contact_center_publish'])
    expect(policy.publish?).to be(false)
  end

  it 'does not allow native administrator fallback to override an explicit denial' do
    member.update!(role: :administrator, custom_role: nil)
    grant.update!(denied: %w[jrc_contact_center_configure jrc_contact_center_reports])
    expect(policy.configure?).to be(false)
    expect(policy.reports?).to be(false)
    expect(policy.supervise?).to be(true)
  end

  it 'does not bypass a configure denial through the administer alias' do
    grant.update!(allowed: ['jrc_contact_center_administer'], denied: ['jrc_contact_center_configure'])
    expect(policy.administer?).to be(true)
    expect(policy.configure?).to be(false)
  end

  it 'requires recording view for both listening and downloading' do
    grant.update!(allowed: %w[jrc_contact_center_recordings_listen jrc_contact_center_recordings_download])
    expect(policy.recordings_listen?).to be(false)
    expect(policy.recordings_download?).to be(false)
  end

  it 'applies a view denial before every individual or inherited operation' do
    grant.update!(allowed: JrcContactCenter::ModulePolicy::PERMISSIONS, denied: ['jrc_contact_center_view'])
    expect(policy.effective_permissions).to eq([])
  end

  it 'revokes inheritance immediately after native membership removal' do
    team.add_members([user.id])
    JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: ['jrc_contact_center_publish'])
    expect(policy.publish?).to be(true)
    team.remove_members([user.id])
    fresh = JrcContactCenter::ModulePolicy.new(context, :contact_center)
    expect(fresh.publish?).to be(false)
  end

  it 'does not trust a malformed membership pointing to a team from another account' do
    foreign_team = create(:team, account: create(:account))
    foreign_team.add_members([user.id])
    JrcContactCenter::AccessGrant.create!(account: foreign_team.account, team: foreign_team, allowed: ['jrc_contact_center_publish'])
    expect(policy.publish?).to be(false)
  end

  it 'does not use a member belonging to another account to obtain legacy access' do
    foreign = create(:account)
    foreign.enable_features!('jrc_contact_center')
    forged = JrcContactCenter::ModulePolicy.new(context.merge(account: foreign), :contact_center)
    expect(forged.effective_permissions).to eq([])
  end

  it 'does not use a different user identity with an eligible member context' do
    stranger = create(:user, account: account)
    forged = JrcContactCenter::ModulePolicy.new(context.merge(user: stranger), :contact_center)
    expect(forged.effective_permissions).to eq([])
  end

  it 'keeps functional grants independent of corporate scope and queue membership' do
    grant.update!(allowed: %w[jrc_contact_center_configure jrc_contact_center_supervise])
    company = account.master_companies.create!(name: 'SYNTHETIC issuer', relationship_type: 'internal')
    JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: 'SYNTHETIC unit', code: 'SYNTHETIC')
    operational = JrcContactCenter::Unit.create!(account: account, name: 'Unmapped', code: 'UNMAPPED', kind: 'sac')
    access = JrcContactCenter::AccessScope.new(user_context: context)
    expect(policy.configure?).to be(true)
    expect(access.units).not_to include(operational)
    expect(JrcCrm::UserBusinessUnit.where(account: account, user: user)).to be_empty
  end

  it 'identifies the native profile and each actual team without changing effective permissions' do
    team.add_members([user.id])
    JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: ['jrc_contact_center_monitor'])
    previous = policy.effective_permissions
    origins = described_class.new(account: account, member: member).origins
    expect(origins[:profile]).to eq(id: role.id, name: role.name, permissions: ['jrc_contact_center_view'])
    expect(origins[:teams]).to eq([{ id: team.id, name: team.name, permissions: ['jrc_contact_center_monitor'] }])
    expect(JrcContactCenter::ModulePolicy.new(context, :contact_center).effective_permissions).to eq(previous)
  end

  it 'does not expose origins from a foreign native team even with a malformed membership' do
    foreign = create(:team, account: create(:account), name: 'SYNTHETIC foreign origin')
    foreign.add_members([user.id])
    JrcContactCenter::AccessGrant.create!(account: foreign.account, team: foreign, allowed: ['jrc_contact_center_publish'])
    origins = described_class.new(account: account, member: member).origins
    expect(origins[:teams]).to eq([])
    expect(origins.to_json).not_to include(foreign.name)
    expect(policy.publish?).to be(false)
  end
end
