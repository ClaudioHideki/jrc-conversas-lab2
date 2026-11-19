require 'rails_helper'

RSpec.describe JrcCrm::TeamMembershipProjection do
  let(:account) { create(:account) }
  let(:operator) { create(:user, account: account) }
  let(:team) { create(:team, account: account) }
  let(:other_team) { create(:team, account: account) }
  let(:source) do
    account.jrc_crm_user_business_units.create!(user: operator, team: team, scope: 'GROUP', structure_managed: true)
  end
  let(:projection) { described_class.new(account: account, team: team, user_ids: []) }
  let(:coverage) { JrcCrm::CorporateCoverage.new(account: account, user: operator, team_membership_projection: projection) }

  before do
    team.add_members([operator.id])
    account.jrc_crm_team_scopes.create!(team: team, scope: 'GROUP')
    source
  end

  it 'withdraws only the proposed team source without changing its stored grant or membership' do
    original = team.team_members.sole.id
    expect(coverage).not_to be_group
    expect(JrcCrm::CorporateCoverage.new(account: account, user: operator)).to be_group
    expect(team.team_members.reload.pluck(:id)).to eq([original])
    expect(source.reload).to be_active
  end

  it 'preserves an independent direct grant during a prospective withdrawal' do
    account.jrc_crm_user_business_units.create!(user: operator, scope: 'GROUP', structure_managed: true)
    expect(coverage).to be_group
    expect(team.members).to include(operator)
  end

  it 'preserves a valid independent team source' do
    other_team.add_members([operator.id])
    account.jrc_crm_team_scopes.create!(team: other_team, scope: 'GROUP')
    account.jrc_crm_user_business_units.create!(user: operator, team: other_team, scope: 'GROUP', structure_managed: true)
    expect(coverage).to be_group
  end

  it 'can evaluate reactivation of a dormant source without actually rejoining the team' do
    team.remove_members([operator.id])
    proposed = described_class.new(account: account, team: team, user_ids: [operator.id.to_s])
    preview = JrcCrm::CorporateCoverage.new(account: account, user: operator, team_membership_projection: proposed)
    expect(preview).to be_group
    expect(JrcCrm::CorporateCoverage.new(account: account, user: operator)).not_to be_group
    expect(team.team_members.reload).to be_empty
  end

  it 'does not create corporate coverage merely by proposing team membership' do
    source.destroy!
    proposed = described_class.new(account: account, team: team, user_ids: [operator.id])
    preview = JrcCrm::CorporateCoverage.new(account: account, user: operator, team_membership_projection: proposed)
    expect(preview).not_to be_group
    expect(account.jrc_crm_user_business_units).to be_empty
  end

  it 'retains the native requirement for an active containing team scope' do
    team_scope = account.jrc_crm_team_scopes.find_by!(team: team)
    team_scope.update!(active: false)
    proposed = described_class.new(account: account, team: team, user_ids: [operator.id])
    preview = JrcCrm::CorporateCoverage.new(account: account, user: operator, team_membership_projection: proposed)
    expect(preview).not_to be_group
    expect(source.reload).to be_active
  end

  it 'refuses a foreign account team before constructing a projection' do
    foreign = create(:team, account: create(:account))
    expect do
      described_class.new(account: account, team: foreign, user_ids: [operator.id])
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'refuses a user who has no membership in the account' do
    foreign = create(:user, account: create(:account))
    expect do
      described_class.new(account: account, team: team, user_ids: [foreign.id])
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'refuses reuse of a valid projection in another account' do
    foreign = create(:account)
    expect do
      projection.team_ids(account: foreign, user: operator, current: foreign.teams.select(:id))
    end.to raise_error(ActiveRecord::RecordNotFound)
  end
end
