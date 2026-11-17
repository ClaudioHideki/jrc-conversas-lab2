require 'rails_helper'

RSpec.describe 'Call Center global ACW configuration scope', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC issuer', relationship_type: 'internal') }
  let(:unit) { JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: 'SYNTHETIC unit', code: 'SYNTHETIC') }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center/acw_policy" }
  let(:attributes) { { limits: { voice: 60, whatsapp: 120 }, voice_required: false } }

  before { account.enable_features!('jrc_contact_center') }

  it 'does not let unit coverage change the policy for the entire account' do
    JrcCrm::UserBusinessUnit.create!(
      account: account, user: actor, scope: 'BUSINESS_UNIT', company: company, business_unit: unit, active: true, structure_managed: true
    )
    previous = JrcContactCenter::AcwPolicy.new(account: account).call
    patch base, headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::AcwPolicy.new(account: account.reload).call).to eq(previous)
    get base.sub('acw_policy', 'administration'), headers: headers
    expect(response.parsed_body.dig('capabilities', 'configuration_global')).to be(false)
  end

  it 'lets explicit GROUP coverage change only its own account policy' do
    unit
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'GROUP', active: true, structure_managed: true)
    patch base, headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:ok)
    expect(JrcContactCenter::AcwPolicy.new(account: account.reload).call[:limits]).to eq('voice' => 60, 'whatsapp' => 120)
    expect(JrcContactCenter::AcwPolicy.new(account: create(:account)).call[:limits]).to eq('voice' => 180, 'whatsapp' => 180)
    get base.sub('acw_policy', 'administration'), headers: headers
    expect(response.parsed_body.dig('capabilities', 'configuration_global')).to be(true)
  end

  it 'does not treat GROUP coverage as permission to configure the module' do
    unit
    account.enable_features!('custom_roles')
    role = create(:custom_role, account: account, permissions: ['jrc_contact_center_view'])
    account.account_users.find_by!(user: actor).update!(custom_role: role)
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'GROUP', active: true, structure_managed: true)
    previous = JrcContactCenter::AcwPolicy.new(account: account).call
    patch base, headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::AcwPolicy.new(account: account.reload).call).to eq(previous)
  end
end
