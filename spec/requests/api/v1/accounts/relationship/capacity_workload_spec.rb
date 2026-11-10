require 'rails_helper'

RSpec.describe 'Native relationship workload editing', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:record) do
    JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account),
                                        settings: { 'private_test_key' => 'must remain', 'complexity' => 'high' })
  end
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/portfolio/#{record.id}" }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'persists typed equivalent hours through the actual native API without discarding existing settings' do
    patch url, headers: headers, as: :json, params: { assignment: { settings: { capacity_workload: { hours: 2.5 } } } }
    expect(response).to have_http_status(:ok), response.body
    expect(record.reload.settings).to include('private_test_key' => 'must remain', 'complexity' => 'high', 'capacity_workload' => { 'hours' => 2.5 })
    patch url, headers: headers, as: :json, params: { assignment: { settings: { capacity_workload: { hours: -1 } } } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(record.reload.settings.dig('capacity_workload', 'hours')).to eq(2.5)
  end

  it 'does not allow another account to edit the workload of a known customer allocation' do
    outsider = create(:user, account: create(:account), role: :administrator)
    patch url, headers: outsider.create_new_auth_token, as: :json, params: { assignment: { settings: { capacity_workload: { hours: 2.5 } } } }
    expect(response).to have_http_status(:forbidden)
    expect(record.reload.settings).not_to have_key('capacity_workload')
  end
end
