require 'rails_helper'

RSpec.describe 'Required registered voice ending reasons', type: :request do
  include_context 'with a frozen ending reason catalogue'

  let(:headers) { actor.create_new_auth_token }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/qualifications/#{record.id}" }

  it 'returns only the frozen active choices to the current own attendance and prevents caching' do
    get "#{endpoint}/form_context", headers: headers, params: { reason_code: '' }
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.parsed_body.dig('item', 'ending_reason_context', 'options')).to eq([entry.slice('code', 'name')])
    expect(response.parsed_body.to_json).not_to include('source_audit_id', 'required_queue_ids', 'actor_user_id', 'description')
  end

  it 'rejects an unregistered reason over the real API then persists the explicit registered completion' do
    patch endpoint, headers: headers, params: { qualification: { reason_code: 'resolved', outcome_code: 'completed' } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(record.reload.completed_at).to be_nil
    patch endpoint, headers: headers, params: { qualification: { reason_code: entry.fetch('code'), outcome_code: 'completed' } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(record.reload.reason_code).to eq(entry.fetch('code'))
  end

  it 'does not allow a second administrator to read another agents private ending reason context' do
    other = create(:user, :contact_center_eligible, account: account, role: :administrator)
    get "#{endpoint}/form_context", headers: other.create_new_auth_token, params: { reason_code: entry.fetch('code') }
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(entry.fetch('name'))
    expect(record.reload.completed_at).to be_nil
  end

  it 'does not allow a foreign account administrator to use a real qualification identifier as a grant' do
    foreign = create(:account)
    other = create(:user, :contact_center_eligible, account: foreign, role: :administrator)
    foreign.enable_features!('jrc_contact_center')
    get "#{endpoint}/form_context", headers: other.create_new_auth_token, params: { reason_code: entry.fetch('code') }
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(entry.fetch('name'))
  end

  it 'denies the immutable original unit after a profile change even if the current call is moved into the new unit' do
    id = record.id
    company = account.master_companies.create!(name: 'SYNTHETIC issuer', relationship_type: 'internal')
    business = JrcCrm::BusinessUnit.create!(account: account, operating_company: company, code: 'SYNTHETIC', name: 'SYNTHETIC covered unit')
    permitted = JrcContactCenter::Unit.create!(account: account, code: 'SYNTHETIC-B', name: 'SYNTHETIC mapped', kind: 'sac',
                                               settings: { issuer_company_id: company.id, business_unit_id: business.id })
    session.update!(current_unit: permitted, current_queue: nil)
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'BUSINESS_UNIT', business_unit: business, company: company,
                                     active: true, structure_managed: true)
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/qualifications/#{id}/form_context", headers: headers, params: { reason_code: '' }
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(entry.fetch('name'))
    expect(record.reload.completed_at).to be_nil
  end
end
