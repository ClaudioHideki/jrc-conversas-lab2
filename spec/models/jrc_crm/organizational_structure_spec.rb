require 'rails_helper'

RSpec.describe 'JRC CRM organizational structure' do
  let(:account) { create(:account) }
  let(:user) { create(:user) }
  let!(:account_user) { create(:account_user, account: account, user: user) }
  let(:company) do
    account.master_companies.create!(name: 'Empresa Operacional', person_kind: 'organization', relationship_type: 'internal')
  end
  let(:unit) { JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: 'Unidade A', code: 'UNIT-A') }
  let(:team) { create(:team, account: account, name: 'Financeiro do Grupo') }

  it 'links business units to an internal master company from the same account' do
    expect(unit.operating_company).to eq(company)
    expect(unit.account_id).to eq(company.account_id)
  end

  it 'allows a shared department to cover the entire group' do
    scope = JrcCrm::TeamScope.create!(account: account, team: team, scope: 'GROUP')

    expect(scope).to be_active
    expect(scope.covers?(company_id: company.id, business_unit_id: unit.id)).to be(true)
  end

  it 'allows company-level department coverage' do
    scope = JrcCrm::TeamScope.create!(account: account, team: team, company: company, scope: 'COMPANY')

    expect(scope.covers?(company_id: company.id, business_unit_id: unit.id)).to be(true)
  end

  it 'limits a user inside the selected department coverage' do
    create(:team_member, team: team, user: user)
    JrcCrm::TeamScope.create!(account: account, team: team, company: company, scope: 'COMPANY')

    record = JrcCrm::UserBusinessUnit.create!(
      account: account, user: user, team: team, company: company,
      scope: 'COMPANY', structure_managed: true, permissions: {}
    )

    expect(record).to be_valid
  end

  it 'rejects a user scope outside the selected department coverage' do
    create(:team_member, team: team, user: user)
    JrcCrm::TeamScope.create!(account: account, team: team, business_unit: unit, company: company, scope: 'BUSINESS_UNIT')
    other_company = account.master_companies.create!(name: 'Outra Empresa', person_kind: 'organization', relationship_type: 'internal')

    record = JrcCrm::UserBusinessUnit.new(
      account: account, user: user, team: team, company: other_company,
      scope: 'COMPANY', structure_managed: true, permissions: {}
    )

    expect(record).not_to be_valid
    expect(record.errors.full_messages.join(' ')).to include('coverage')
  end

  it 'keeps functional permissions separate from organizational coverage' do
    create(:team_member, team: team, user: user)
    JrcCrm::TeamScope.create!(account: account, team: team, company: company, scope: 'COMPANY')
    record = JrcCrm::UserBusinessUnit.create!(
      account: account, user: user, team: team, company: company,
      scope: 'COMPANY', structure_managed: true, permissions: {}
    )

    expect(record.permissions).to eq({})
    expect(account_user.role).to eq('agent')
  end
  it 'applies configured company coverage as a restrictive visibility boundary' do
    other_company = account.master_companies.create!(name: 'Empresa B', person_kind: 'organization', relationship_type: 'internal')
    other_unit = JrcCrm::BusinessUnit.create!(account: account, operating_company: other_company, name: 'Unidade B', code: 'UNIT-B')
    JrcCrm::UserBusinessUnit.create!(account: account, user: user, company: company, scope: 'COMPANY',
                                    structure_managed: true, permissions: {})
    account.update!(custom_attributes: account.custom_attributes.merge('jrc_crm_organization' => { 'scope_enforcement_enabled' => true }))

    visible = JrcCrm::OrganizationalVisibility.new(
      account: account, user: user, relation: JrcCrm::BusinessUnit.where(account_id: account.id)
    ).call

    expect(visible).to include(unit)
    expect(visible).not_to include(other_unit)
  end

  it 'preserves legacy visibility when a user has no configured organizational coverage' do
    account.update!(custom_attributes: account.custom_attributes.merge('jrc_crm_organization' => { 'scope_enforcement_enabled' => true }))
    relation = JrcCrm::BusinessUnit.where(account_id: account.id)

    expect(JrcCrm::OrganizationalVisibility.new(account: account, user: user, relation: relation).call.to_sql).to eq(relation.to_sql)
  end

end
