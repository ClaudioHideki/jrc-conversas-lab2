require 'rails_helper'

RSpec.describe 'Native corporate-scope writes used by Call Center', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:recipient) { create(:user, account: account) }
  let!(:headers) { actor.create_new_auth_token }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC issuer', relationship_type: 'internal') }
  let(:unit) { account.jrc_crm_business_units.create!(name: 'SYNTHETIC unit', code: 'A', operating_company: company) }
  let(:team) { create(:team, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/organization_structure" }
  let(:group) { account.jrc_crm_user_business_units.create!(user: actor, scope: 'GROUP', structure_managed: true) }

  before do
    account.enable_features!('jrc_crm', 'audit_logs')
    unit
    group
  end

  it 'keeps native team-scope creation, narrowing, deactivation and deletion functional' do
    post "#{base}/team_scopes", headers: headers, params: { team_scope: { team_id: team.id, scope: 'GROUP' } }, as: :json
    expect(response).to have_http_status(:created)
    scope = account.jrc_crm_team_scopes.find_by!(team: team)
    payload = { team_scope: { team_id: team.id, scope: 'BUSINESS_UNIT', business_unit_id: unit.id, active: false } }
    patch "#{base}/team_scopes/#{scope.id}", headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:ok)
    expect(scope.reload).to have_attributes(scope: 'BUSINESS_UNIT', business_unit_id: unit.id, active: false)
    delete "#{base}/team_scopes/#{scope.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(account.jrc_crm_team_scopes.exists?(scope.id)).to be(false)
  end

  it 'keeps native user-scope creation, narrowing, deactivation and deletion functional' do
    post "#{base}/user_scopes", headers: headers, params: { user_scope: { user_id: recipient.id, scope: 'GROUP' } }, as: :json
    expect(response).to have_http_status(:created)
    scope = account.jrc_crm_user_business_units.find_by!(user: recipient)
    payload = { user_scope: { user_id: recipient.id, scope: 'COMPANY', company_id: company.id, active: false } }
    patch "#{base}/user_scopes/#{scope.id}", headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:ok)
    expect(scope.reload).to have_attributes(scope: 'COMPANY', company_id: company.id, active: false, permissions: {})
    delete "#{base}/user_scopes/#{scope.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(account.jrc_crm_user_business_units.exists?(scope.id)).to be(false)
  end

  it 'does not let native administrator role replace a revoked Group source' do
    group.update!(active: false)
    expect do
      post "#{base}/team_scopes", headers: headers, params: { team_scope: { team_id: team.id, scope: 'GROUP' } }, as: :json
    end.not_to change(JrcCrm::TeamScope, :count)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'does not let a Group source replace the native administrative permission' do
    account.account_users.find_by!(user: actor).update!(role: :agent)
    post "#{base}/user_scopes", headers: headers, params: { user_scope: { user_id: recipient.id, scope: 'GROUP' } }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(account.jrc_crm_user_business_units.where(user: recipient)).to be_empty
  end

  it 'rejects foreign team identifiers without persisting a corporate scope' do
    foreign = create(:team, account: create(:account))
    post "#{base}/team_scopes", headers: headers, params: { team_scope: { team_id: foreign.id, scope: 'GROUP' } }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(account.jrc_crm_team_scopes).to be_empty
  end
end
