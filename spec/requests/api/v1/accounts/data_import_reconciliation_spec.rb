require 'rails_helper'

RSpec.describe 'Data import reconciliation API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:data_import) { create(:data_import, :intercom, account: account, import_types: ['contacts'], status: :completed) }
  let(:path) { "/api/v1/accounts/#{account.id}/data_imports/#{data_import.id}/reconciliation" }

  before { account.enable_features!('data_import') }

  it 'reports unknown source totals without changing the import or approving migration', :aggregate_failures do
    original = data_import.reload.attributes

    get path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body).to include('data_import_id' => data_import.id, 'source_checked' => false, 'acceptance' => 'not_reviewed')
    expect(body.fetch('entities').first).to include('type' => 'contact', 'source_total' => nil, 'comparison' => 'unknown')
    expect(body).not_to have_key('access_token')
    expect(data_import.reload.attributes).to eq(original)
    expect(data_import.items).to be_empty
    expect(data_import.mappings).to be_empty
    expect(data_import.import_errors).to be_empty
  end

  it 'refuses a non-administrator even within the same account' do
    agent = create(:user, account: account, role: :agent)

    get path, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'does not disclose an import belonging to another account' do
    foreign_import = create(:data_import, :intercom)

    get "/api/v1/accounts/#{account.id}/data_imports/#{foreign_import.id}/reconciliation",
        headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end

  it 'requires the existing data_import feature flag' do
    account.disable_features!('data_import')

    get path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
