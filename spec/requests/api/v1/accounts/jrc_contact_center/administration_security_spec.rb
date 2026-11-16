require 'rails_helper'

RSpec.describe 'Call Center administration isolation', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: user) }
  let(:headers) { user.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center" }
  before { account.enable_features!('jrc_contact_center') }

  it 'does not grant new recording/publication/approval/audit authorities to a native administrator' do
    policy = JrcContactCenter::ModulePolicy.new({ account: account, user: user, account_user: member }, :contact_center)
    expect(policy.configure?).to be(true)
    %i[recordings_view? recordings_listen? recordings_download? publish? approve? audit? administer? monitor?].each do |action|
      expect(policy.public_send(action)).to be(false)
    end
    get "#{base}/administration/audit", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'does not automatically activate a newly created unassigned agent' do
    agent = create(:user, account: account, role: :agent)
    get "#{base}/context", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'keeps publication blocked without permission or a provider contract' do
    unit = JrcContactCenter::Unit.create!(account: account, code: 'TEST', name: 'Test', kind: 'sac')
    post "#{base}/routing_rules", params: { routing_rule: { rule_key: 'TEST', version: 1, kind: 'ddd', target_unit_id: unit.id,
                                                          priority: 1, state: 'published' } }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::RoutingRule.where(account: account)).to be_empty
  end

  it 'paginates and filters real units deterministically' do
    3.times { |index| JrcContactCenter::Unit.create!(account: account, code: "TEST#{index}", name: "Synthetic #{index}", kind: 'sac') }
    get "#{base}/units", params: { page: 1, per_page: 2, q: 'Synthetic' }, headers: headers
    ids = response.parsed_body.fetch('items').pluck('id')
    expect(response.parsed_body.fetch('meta')).to include('total' => 3, 'pages' => 2)
    get "#{base}/units", params: { page: 2, per_page: 2, q: 'Synthetic' }, headers: headers
    expect(response.parsed_body.fetch('items').pluck('id') & ids).to be_empty
  end

  it 'does not allow the Account URL to reveal another Account administration' do
    other = create(:account)
    get "/api/v1/accounts/#{other.id}/jrc_contact_center/administration", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'intersects operational units with corporate business units even for an administrator' do
    company = JrcCustomers::Company.create!(account: account, name: 'Synthetic issuer', relationship_type: 'internal', active: true)
    first = JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: 'Unit A', code: 'UNIT-A', active: true)
    second = JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: 'Unit B', code: 'UNIT-B', active: true)
    JrcCrm::UserBusinessUnit.create!(account: account, user: user, scope: 'BUSINESS_UNIT', business_unit: first,
                                    company: company, active: true, structure_managed: true)
    allowed = JrcContactCenter::Unit.create!(account: account, name: 'Allowed', code: 'ALLOWED', kind: 'sac',
                                            settings: { issuer_company_id: company.id, business_unit_id: first.id })
    denied = JrcContactCenter::Unit.create!(account: account, name: 'Denied', code: 'DENIED', kind: 'sac',
                                           settings: { issuer_company_id: company.id, business_unit_id: second.id })
    get "#{base}/units", headers: headers
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([allowed.id])
    patch "#{base}/units/#{denied.id}", params: { unit: { name: 'Forbidden' } }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(denied.reload.name).to eq('Denied')
  end
end
