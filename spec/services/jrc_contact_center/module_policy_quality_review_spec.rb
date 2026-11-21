require 'rails_helper'

RSpec.describe JrcContactCenter::ModulePolicy, '#quality_review?' do
  let(:account) { create(:account) }
  let(:user) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: user) }
  let(:grant) { JrcContactCenter::AccessGrant.find_by!(account_user: member) }
  let(:review) { 'jrc_contact_center_quality_review' }
  let(:recording) { %w[jrc_contact_center_view jrc_contact_center_recordings_view jrc_contact_center_recordings_listen] }
  let(:role) { create(:custom_role, account: account, permissions: recording) }
  let(:team) { create(:team, account: account) }

  before do
    account.enable_features!('jrc_contact_center')
    member.update!(custom_role: role)
  end

  def policy(overrides = {})
    context = { account: account.reload, account_user: member.reload, user: user }.merge(overrides)
    described_class.new(context, :contact_center)
  end

  def team_review
    team.add_members([user.id])
    JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: [review])
  end

  it 'does not infer review from any of the thirteen existing rights or native administration' do
    role.update!(permissions: described_class::PERMISSIONS - [review])
    expect(policy.recordings_listen?).to be(true)
    expect(policy.quality_review?).to be(false)
    member.update!(role: :administrator, custom_role: nil)
    expect(policy.configure?).to be(true)
    expect(policy.quality_review?).to be(false)
  end

  it 'requires an explicit registered profile right in addition to native recording access' do
    role.update!(permissions: recording + [review])
    expect(role.reload.permissions).to include(review)
    expect(policy.quality_review?).to be(true)
    expect(policy.effective_permissions).to include(review)
    expect(policy.recordings_download?).to be(false)
    expect(policy.configure?).to be(false)
    expect(policy.supervise?).to be(false)
  end

  %w[jrc_contact_center_recordings_view jrc_contact_center_recordings_listen].each do |missing|
    it "does not review when the profile lacks #{missing}" do
      role.update!(permissions: (recording + [review]) - [missing])
      expect(policy.quality_review?).to be(false)
      expect(policy.effective_permissions).not_to include(review)
    end
  end

  it 'inherits the explicit right only from an active native team membership' do
    team_review
    expect(policy.quality_review?).to be(true)
    team.remove_members([user.id])
    expect(policy.quality_review?).to be(false)
  end

  it 'suspends only an inactive team source while preserving an explicit individual source' do
    team_review
    expect(policy.quality_review?).to be(true)
    JrcContactCenter::TeamState.create!(account: account, team: team, active: false)
    expect(policy.quality_review?).to be(false)
    grant.update!(allowed: [review])
    expect(policy.quality_review?).to be(true)
    expect(team.team_members.exists?(user: user)).to be(true)
  end

  %w[
    jrc_contact_center_view jrc_contact_center_recordings_view
    jrc_contact_center_recordings_listen jrc_contact_center_quality_review
  ].each do |denied|
    it "honors explicit #{denied} denial over profile, team and individual grants" do
      role.update!(permissions: recording + [review])
      team_review
      grant.update!(allowed: [review], denied: [denied])
      expect(policy.quality_review?).to be(false)
      expect(policy.effective_permissions).not_to include(review)
    end
  end

  it 'does not activate an ineligible member even with an explicit profile and team' do
    role.update!(permissions: recording + [review])
    team_review
    grant.update!(eligible: false)
    expect(policy.quality_review?).to be(false)
    expect(policy.effective_permissions).to eq([])
  end

  it 'never inherits the legacy recording bypass when the module is disabled' do
    role.update!(permissions: recording + [review])
    account.disable_features!('jrc_contact_center')
    expect(policy.quality_review?).to be(false)
    expect(policy.effective_permissions).not_to include(review)
  end

  it 'rejects a foreign team even with an inconsistent native membership' do
    foreign = create(:team, account: create(:account))
    foreign.add_members([user.id])
    JrcContactCenter::AccessGrant.create!(account: foreign.account, team: foreign, allowed: [review])
    expect(policy.quality_review?).to be(false)
  end

  it 'rejects a forged account or user context without exporting the new capability' do
    role.update!(permissions: recording + [review])
    foreign = create(:account)
    foreign.enable_features!('jrc_contact_center')
    stranger = create(:user, account: account)
    expect(policy(account: foreign).quality_review?).to be(false)
    expect(policy(user: stranger).quality_review?).to be(false)
  end

  it 'does not let an administrator mint the review right through the native grant guard' do
    member.update!(role: :administrator, custom_role: nil)
    grant.update!(allowed: recording)
    expect { JrcContactCenter::GrantGuard.check!(actor: user, account: account, proposed: [review]) }
      .to raise_error(Pundit::NotAuthorizedError)
  end

  it 'uses the same native grant guard for an explicitly authorized synthetic reviewer' do
    role.update!(permissions: recording + [review])
    expect { JrcContactCenter::GrantGuard.check!(actor: user, account: account, proposed: [review]) }.not_to raise_error
    expect(JrcContactCenter::AccessGrant.find_by!(account_user: member).allowed).to eq([])
  end
end
