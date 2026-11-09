# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Account-scoped Service Desk establishment lookup', type: :request do
  include_context 'JRC Service Desk domain'

  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/establishments" }
  let(:headers) { sd_user.create_new_auth_token }

  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master')
  end

  it 'returns an authorized empty result when stores are disabled without failing the controller scope verification' do
    get base, params: { unit_id: sd_unit.id }, headers: headers

    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body).to eq('enabled' => false, 'establishments' => [])
  end

  it 'never resolves a unit from another Account' do
    get base, params: { unit_id: sd_foreign_unit.id }, headers: headers

    expect(response).to have_http_status(:not_found)
  end
end
