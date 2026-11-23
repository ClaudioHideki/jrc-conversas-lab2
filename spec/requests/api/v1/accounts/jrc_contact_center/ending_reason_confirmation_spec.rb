require 'rails_helper'

RSpec.describe 'Explicit own-attendance ending reason confirmation', type: :request do
  include_context 'with a frozen ending reason catalogue'

  let(:headers) { actor.create_new_auth_token }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/qualifications/#{record.id}/confirm_reason" }
  let(:input) do
    { qualification: { reason_code: entry.fetch('code'), notes: 'SYNTHETIC private note' },
      expected_draft_revision: JrcContactCenter::QualificationDraftRevision.token(record), idempotency_key: SecureRandom.uuid }
  end

  it 'returns a private no-store confirmation while leaving the existing ACW pending' do
    post endpoint, headers: headers, params: input, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.parsed_body.dig('item', 'ending_reason_confirmation')).to include('state' => 'confirmed', 'completes_acw' => false)
    expect(record.reload.completed_at).to be_nil
    expect(record.notes).to eq('SYNTHETIC private note')
    expect(response.parsed_body.to_json).not_to include('input_digest', 'source_event_id', 'actor_user_id')
  end

  it 'refuses another account credential and does not reveal the private classification' do
    foreign = create(:account)
    outsider = create(:user, :contact_center_eligible, account: foreign, role: :administrator)
    post endpoint, headers: outsider.create_new_auth_token, params: input, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(entry.fetch('name'), 'SYNTHETIC private note')
    expect(JrcContactCenter::EndingReasonConfirmation.where(account: account)).to be_empty
  end

  it 'does not grant a second administrator authority over the original operator classification' do
    other = create(:user, :contact_center_eligible, account: account, role: :administrator)
    post endpoint, headers: other.create_new_auth_token, params: input, as: :json
    expect(response).to have_http_status(:not_found)
    expect(JrcContactCenter::EndingReasonConfirmation.where(account: account)).to be_empty
  end

  it 'rejects submitted authority identifiers instead of using them to select a different scope' do
    post endpoint, headers: headers, params: input.merge(unit_id: unit.id, user_id: actor.id), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::EndingReasonConfirmation.where(account: account)).to be_empty
    expect(record.reload.reason_code).to be_nil
  end

  it 'rejects a changed reason on the normal draft API after confirmation' do
    post endpoint, headers: headers, params: input, as: :json
    expect(response).to have_http_status(:ok)
    revision = response.parsed_body.dig('item', 'draft_revision')
    body = { qualification: { reason_code: 'other' }, expected_draft_revision: revision }
    patch endpoint.sub('/confirm_reason', '/draft'), headers: headers, params: body, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('ending_reason_already_confirmed')
    expect(record.reload.completed_at).to be_nil
  end

  it 'requires JSON and rejects a missing request key without modifying the pending record' do
    post endpoint, headers: headers, params: input.except(:idempotency_key), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::EndingReasonConfirmation.where(account: account)).to be_empty
    post endpoint, headers: headers, params: input
    expect(response).to have_http_status(:unprocessable_entity)
    expect(record.reload.completed_at).to be_nil
  end

  it 'does not use a moved current call unit to override the immutable original operating scope' do
    id = record.id
    company = account.master_companies.create!(name: 'SYNTHETIC issuer', relationship_type: 'internal')
    business = JrcCrm::BusinessUnit.create!(account: account, operating_company: company, code: 'SYNTHETIC', name: 'SYNTHETIC covered unit')
    permitted = JrcContactCenter::Unit.create!(account: account, code: 'SYNTHETIC-B', name: 'SYNTHETIC mapped', kind: 'sac',
                                               settings: { issuer_company_id: company.id, business_unit_id: business.id })
    session.update!(current_unit: permitted, current_queue: nil)
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'BUSINESS_UNIT', business_unit: business, company: company,
                                     active: true, structure_managed: true)
    body = { qualification: { reason_code: entry.fetch('code') }, expected_draft_revision: 'irrelevant-no-authority',
             idempotency_key: SecureRandom.uuid }
    post "/api/v1/accounts/#{account.id}/jrc_contact_center/qualifications/#{id}/confirm_reason", headers: headers, params: body, as: :json
    expect(response).to have_http_status(:not_found)
    expect(JrcContactCenter::EndingReasonConfirmation.where(account: account)).to be_empty
    expect(record.reload.completed_at).to be_nil
  end

  it 'rejects replay after current operating eligibility is revoked without treating the stored confirmation as an access grant' do
    body = input
    post endpoint, headers: headers, params: body, as: :json
    expect(response).to have_http_status(:ok)
    JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member).update!(eligible: false)
    post endpoint, headers: headers, params: body, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('SYNTHETIC private note')
    expect(JrcContactCenter::EndingReasonConfirmation.where(account: account).count).to eq(1)
  end
end
