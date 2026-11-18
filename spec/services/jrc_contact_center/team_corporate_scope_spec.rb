require 'rails_helper'

RSpec.describe 'Current native team corporate coverage in Call Center' do
  let(:account) { create(:account) }
  let(:operator) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: operator) }
  let(:role) { create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_configure]) }
  let(:company) { JrcCustomers::Company.create!(account: account, name: 'SYNTHETIC issuer A', relationship_type: 'internal') }
  let(:other_company) { JrcCustomers::Company.create!(account: account, name: 'SYNTHETIC issuer B', relationship_type: 'internal') }
  let(:business_unit) { JrcCrm::BusinessUnit.create!(account: account, operating_company: company, code: 'A', name: 'SYNTHETIC business A') }
  let(:other_business_unit) do
    JrcCrm::BusinessUnit.create!(account: account, operating_company: other_company, code: 'B', name: 'SYNTHETIC business B')
  end
  let(:unit) do
    JrcContactCenter::Unit.create!(account: account, code: 'A', name: 'SYNTHETIC operational A', kind: 'sac',
                                   settings: { issuer_company_id: company.id, business_unit_id: business_unit.id })
  end
  let(:other_unit) do
    JrcContactCenter::Unit.create!(account: account, code: 'B', name: 'SYNTHETIC operational B', kind: 'sac',
                                   settings: { issuer_company_id: other_company.id, business_unit_id: other_business_unit.id })
  end
  let(:team) { create(:team, account: account) }
  let(:team_scope) { JrcCrm::TeamScope.create!(account: account, team: team, scope: 'COMPANY', company: company, active: true) }
  let(:source) do
    JrcCrm::UserBusinessUnit.create!(account: account, user: operator, team: team, company: company,
                                     scope: 'COMPANY', structure_managed: true, active: true)
  end
  let(:coverage) { JrcCrm::CorporateCoverage.new(account: account, user: operator) }
  let(:access) { JrcContactCenter::AccessScope.new(user_context: { account: account, account_user: member, user: operator }) }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles')
    member.update!(custom_role: role)
    unit
    other_unit
    team.add_members([operator.id])
    team_scope
    source
  end

  it 'reuses a valid native team-linked company scope without creating another grant' do
    expect(access.units.pluck(:id)).to eq([unit.id])
    expect(coverage.company_ids.pluck(:id)).to eq([company.id])
    expect(source.reload).to be_active
  end

  it 'withdraws a source after membership removal even when the stored grant is still marked active' do
    expect(access.units.pluck(:id)).to eq([unit.id])
    team.remove_members([operator.id])
    expect(source.reload).to be_active
    expect(access.units).to be_empty
    expect(coverage.company_ids).to be_empty
    expect(member.reload.custom_role_id).to eq(role.id)
  end

  it 'withdraws an inactive containing team scope without changing functional permissions' do
    team_scope.update!(active: false)
    expect(source.reload).to be_active
    expect(access.policy.configure?).to be(true)
    expect(access.units).to be_empty
    expect(coverage.company_ids).to be_empty
  end

  it 'does not turn a company-wide user scope into authority from a single-unit team scope' do
    team_scope.update!(scope: 'BUSINESS_UNIT', business_unit: business_unit)
    expect(source.reload.scope).to eq('COMPANY')
    expect(access.units).to be_empty
  end

  it 'preserves a unit grant that remains inside a narrowed current team scope' do
    source.update!(scope: 'BUSINESS_UNIT', business_unit: business_unit)
    team_scope.update!(scope: 'BUSINESS_UNIT', business_unit: business_unit)
    expect(access.units.pluck(:id)).to eq([unit.id])
    expect(coverage.unit_ids.pluck(:id)).to eq([business_unit.id])
  end

  it 'withdraws inherited GROUP after the team coverage is narrowed and never falls back to all units' do
    team_scope.update!(scope: 'GROUP', company: nil)
    source.update!(scope: 'GROUP', company: nil)
    expect(coverage).to be_group
    team_scope.update!(scope: 'COMPANY', company: company)
    expect(coverage).not_to be_group
    expect(coverage).to be_configured
    expect(access.units).to be_empty
  end

  it 'preserves independent direct coverage when a team source is withdrawn' do
    JrcCrm::UserBusinessUnit.create!(account: account, user: operator, company: other_company,
                                     scope: 'COMPANY', structure_managed: true, active: true)
    expect(access.units.pluck(:id)).to contain_exactly(unit.id, other_unit.id)
    team.remove_members([operator.id])
    expect(access.units.pluck(:id)).to eq([other_unit.id])
    expect(coverage.company_ids.pluck(:id)).to eq([other_company.id])
  end

  it 'does not grant coverage from team membership or team scope alone' do
    source.destroy!
    expect(team.members).to include(operator)
    expect(team_scope).to be_active
    expect(access.units).to be_empty
  end

  it 'requires both current membership and a valid team scope after reinclusion' do
    team.remove_members([operator.id])
    team_scope.update!(active: false)
    team.add_members([operator.id])
    expect(source.reload).to be_active
    expect(access.units).to be_empty
  end

  it 'does not substitute another team or a foreign account for the withdrawn source' do
    unrelated = create(:team, account: account)
    unrelated.add_members([operator.id])
    account.jrc_crm_team_scopes.create!(team: unrelated, scope: 'GROUP')
    foreign = create(:account)
    create(:account_user, account: foreign, user: operator)
    foreign.jrc_crm_user_business_units.create!(user: operator, scope: 'GROUP', structure_managed: true)
    team_scope.update!(active: false)
    expect(coverage).not_to be_group
    expect(access.units).to be_empty
  end

  it 'does not infer a user grant from an active team scope when the explicit source is inactive' do
    source.update!(active: false)
    expect(team_scope.reload).to be_active
    expect(team.members).to include(operator)
    expect(access.units).to be_empty
  end

  it 'withdraws inherited Group from the existing Backoffice configuration authority after team removal' do
    account.enable_features!('jrc_crm')
    role.update!(permissions: role.permissions + ['jrc_crm'])
    team_scope.update!(scope: 'GROUP', company: nil)
    source.update!(scope: 'GROUP', company: nil)
    expect(JrcBackoffice::SignatureConfiguration.can_manage?(account: account, actor: operator)).to be(true)
    team.remove_members([operator.id])
    expect(JrcBackoffice::SignatureConfiguration.can_manage?(account: account, actor: operator)).to be(false)
    expect(source.reload).to be_active
  end

  it 'withdraws the same native source from approval decisions without changing the functional role' do
    account.enable_features!('jrc_approvals')
    role.update!(permissions: role.permissions + ['jrc_approvals_decide'])
    authorization = JrcApprovals::Authorization.new(account: account, user: operator)
    expect do
      authorization.authorize!('decide', company_id: company.id, unit_id: business_unit.id)
    end.not_to raise_error
    team.remove_members([operator.id])
    expect do
      authorization.authorize!('decide', company_id: company.id, unit_id: business_unit.id)
    end.to raise_error(Pundit::NotAuthorizedError)
    expect(role.reload.permissions).to include('jrc_approvals_decide')
  end
end
