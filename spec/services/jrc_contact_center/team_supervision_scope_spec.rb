require 'rails_helper'

RSpec.describe JrcContactCenter::TeamSupervisionScope do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: user) }
  let(:team) { create(:team, account: account) }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC issuer', relationship_type: 'internal') }
  let(:unit) { account.jrc_crm_business_units.create!(name: 'SYNTHETIC unit', code: 'synthetic', company_id: company.id) }
  let(:requirement) { account.jrc_crm_team_scopes.create!(team: team, scope: 'BUSINESS_UNIT', business_unit: unit) }
  let(:source) do
    account.jrc_crm_user_business_units.create!(user: user, scope: 'BUSINESS_UNIT', business_unit: unit, structure_managed: true)
  end
  let(:boundary) { described_class.new(account: account, team: team, member: member) }

  before do
    requirement
    source
  end

  it 'accepts the exact native unit source without adding the supervisor to that team' do
    expect(boundary).to be_covered
    expect(team.team_members).to be_empty
    expect(JrcContactCenter::AccessGrant.where(account: account, team: team)).to be_empty
  end

  it 'accepts an existing company grant for its unit but does not widen a unit grant to the whole company' do
    requirement.update!(scope: 'COMPANY', company: company, business_unit: nil)
    expect(boundary).not_to be_covered
    source.update!(scope: 'COMPANY', company: company, business_unit: nil)
    expect(boundary).to be_covered
  end

  it 'requires explicit group coverage for a group team, without assuming an administrator grant' do
    requirement.update!(scope: 'GROUP', business_unit: nil)
    member.update!(role: :administrator)
    expect(boundary).not_to be_covered
    source.update!(scope: 'GROUP', business_unit: nil)
    expect(boundary).to be_covered
  end

  it 'requires all active team scopes rather than accepting a single overlapping unit' do
    other = account.jrc_crm_business_units.create!(name: 'SYNTHETIC other unit', code: 'other', company_id: company.id)
    account.jrc_crm_team_scopes.create!(team: team, scope: 'BUSINESS_UNIT', business_unit: other)
    expect(boundary).not_to be_covered
    account.jrc_crm_user_business_units.create!(user: user, scope: 'BUSINESS_UNIT', business_unit: other, structure_managed: true)
    expect(boundary).to be_covered
  end

  it 'does not reuse withdrawn corporate coverage across fresh checks' do
    expect(boundary).to be_covered
    source.update!(active: false)
    expect(boundary).not_to be_covered
  end

  it 'preserves the native unconfigured-account path without manufacturing organizational scopes' do
    requirement.destroy!
    source.destroy!
    unit.destroy!
    expect(boundary).to be_covered
    expect(JrcCrm::TeamScope.where(account: account)).to be_empty
    expect(JrcCrm::UserBusinessUnit.where(account: account)).to be_empty
  end

  it 'requires group coverage for an unscoped team when the corporate structure is configured' do
    requirement.destroy!
    expect(boundary).not_to be_covered
    source.update!(scope: 'GROUP', business_unit: nil)
    expect(boundary).to be_covered
  end

  it 'does not substitute another account team or account member even with a same-shaped group grant' do
    other = create(:account)
    foreign_team = create(:team, account: other)
    foreign_user = create(:user, account: other)
    foreign_member = other.account_users.find_by!(user: foreign_user)
    expect(described_class.new(account: account, team: foreign_team, member: member)).not_to be_covered
    expect(described_class.new(account: account, team: team, member: foreign_member)).not_to be_covered
  end

  it 'rejects a team requirement whose unit became inactive even if the selected user has group coverage' do
    source.update!(scope: 'GROUP', business_unit: nil)
    unit.update!(active: false)
    expect(boundary).not_to be_covered
  end

  it 'does not inherit coverage through an inactive Call Center team while preserving the original CRM source' do
    origin = create(:team, account: account)
    origin.add_members([user.id])
    account.jrc_crm_team_scopes.create!(team: origin, scope: 'GROUP')
    source.update!(team: origin)
    expect(boundary).to be_covered
    JrcContactCenter::TeamState.create!(account: account, team: origin, active: false)
    expect(boundary).not_to be_covered
    expect(JrcCrm::CurrentStructureScopes.new(account: account, user: user).call.exists?(id: source.id)).to be(true)
    expect(source.reload).to be_active
  end
end
