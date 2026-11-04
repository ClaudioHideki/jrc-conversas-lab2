require 'rails_helper'

RSpec.describe 'Protected document responsibility metadata', type: :request do
  let(:account) { create(:account) }
  let(:manager) { create(:user, account: account, role: :administrator) }
  let(:analyst) { create(:user, account: account, role: :agent) }
  let(:headers) { manager.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship/documents" }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: analyst) }
  let(:document) do
    post base, headers: headers, params: { assignment_id: assignment.id, file: fixture_file_upload('jrc_projects_task.txt', 'text/plain'),
                                           document: { title: 'SYNTHETIC protected metadata', category: 'registration',
                                                       change_reason: 'Synthetic initial version' } }
    JrcRelationship::CustomerDocument.find(response.parsed_body.fetch('id'))
  end
  let(:values) { { responsible_id: analyst.id, status: 'active', revision: document.lock_version, reason: 'Explicit documentary responsibility' } }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship') }

  it 'persists explicit responsibility separately from uploader and portfolio owner without releasing quarantined content' do
    versions = document.versions.order(:number).map(&:attributes)
    patch "#{base}/#{document.id}", headers: headers, as: :json, params: { document: values.merge(responsible_id: manager.id) }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('responsible' => { 'id' => manager.id, 'name' => manager.name },
                                            'portfolio_owner' => { 'id' => analyst.id, 'name' => analyst.name }, 'revision' => 1)
    expect(document.reload.responsible_id).to eq(manager.id)
    expect(document.versions.order(:number).map(&:attributes)).to eq(versions)
    expect(response.parsed_body['versions'].first).to include('uploaded_by_id' => manager.id, 'download_available' => false)
    get "#{base}/#{document.id}", headers: headers
    expect(response.parsed_body.dig('responsible', 'id')).to eq(manager.id)
    get "#{base}/#{document.id}/versions/#{document.versions.first.id}/download", headers: headers
    expect(response).to have_http_status(:conflict)
  end

  it 'records an explicit reason and the previous responsibility in the native audit' do
    patch "#{base}/#{document.id}", headers: headers, as: :json, params: { document: values }
    audit = JrcCrm::AuditEvent.where(account: account, resource_type: document.class.name, resource_id: document.id)
                              .find_by!("metadata ->> 'action' = 'document_metadata_updated'")
    expect(audit.from_value).to include('responsible_id' => nil)
    expect(audit.to_value).to include('responsible_id' => analyst.id, 'reason' => 'Explicit documentary responsibility')
  end

  it 'revalidates operator and unit coverage for metadata and eligible-user options' do
    document
    issuer_a = account.master_companies.create!(name: 'SYNTHETIC operator A', relationship_type: 'internal')
    issuer_b = account.master_companies.create!(name: 'SYNTHETIC operator B', relationship_type: 'internal')
    unit_a = account.jrc_crm_business_units.create!(name: 'SYNTHETIC A', code: 'SYN-A', operating_company: issuer_a)
    unit_b = account.jrc_crm_business_units.create!(name: 'SYNTHETIC B', code: 'SYN-B', operating_company: issuer_b)
    account.jrc_crm_user_business_units.create!(user: analyst, company: issuer_a, business_unit: unit_a,
                                                scope: 'BUSINESS_UNIT', structure_managed: true, active: true)
    role = create(:custom_role, account: account, permissions: %w[contact_manage jrc_relationship_view jrc_relationship_documents_manage])
    account.account_users.find_by!(user: analyst).update!(custom_role: role)
    assignment.update!(business_unit: unit_b)
    auth = analyst.create_new_auth_token
    get "#{base}/#{document.id}/responsibles", headers: auth
    expect(response).to have_http_status(:not_found)
    patch "#{base}/#{document.id}", headers: auth, as: :json, params: { document: values }
    expect(response).to have_http_status(:not_found)
    expect(document.reload.responsible_id).to be_nil
    assignment.update!(business_unit: unit_a)
    patch "#{base}/#{document.id}", headers: auth, as: :json, params: { document: values }
    expect(response).to have_http_status(:ok)
    expect(document.reload.responsible_id).to eq(analyst.id)
  end

  it 'does not infer document access from the responsibility assignment' do
    patch "#{base}/#{document.id}", headers: headers, as: :json, params: { document: values }
    expect(response).to have_http_status(:ok)
    get "#{base}/#{document.id}", headers: analyst.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
  end

  it 'denies metadata changes and picker access to an authorized view-only reader' do
    document
    role = create(:custom_role, account: account, permissions: %w[contact_manage jrc_relationship_view jrc_relationship_documents_view])
    account.account_users.find_by!(user: analyst).update!(custom_role: role)
    auth = analyst.create_new_auth_token
    before = document.reload.attributes
    get "#{base}/#{document.id}", headers: auth
    expect(response).to have_http_status(:ok)
    patch "#{base}/#{document.id}", headers: auth, as: :json, params: { document: values }
    expect(response).to have_http_status(:forbidden)
    get "#{base}/#{document.id}/responsibles", headers: auth
    expect(response).to have_http_status(:forbidden)
    expect(document.reload.attributes).to eq(before)
  end

  it 'rejects a stale revision instead of overwriting the current responsible or status' do
    old = values
    patch "#{base}/#{document.id}", headers: headers, as: :json, params: { document: old }
    expect(response).to have_http_status(:ok)
    patch "#{base}/#{document.id}", headers: headers, as: :json, params: { document: old.merge(responsible_id: manager.id, status: 'archived') }
    expect(response).to have_http_status(:conflict)
    expect(document.reload).to have_attributes(responsible_id: analyst.id, status: 'active', lock_version: 1)
  end

  it 'clears responsibility only by explicit choice and preserves versions on archival' do
    patch "#{base}/#{document.id}", headers: headers, as: :json, params: { document: values }
    expect(response).to have_http_status(:ok)
    patch "#{base}/#{document.id}", headers: headers, as: :json,
                                    params: { document: { responsible_id: '', status: 'archived', revision: 1,
                                                          reason: 'Explicit archival without deleting history' } }
    expect(response).to have_http_status(:ok)
    expect(document.reload).to have_attributes(responsible_id: nil, status: 'archived')
    expect(document.versions.count).to eq(1)
  end

  it 'rejects foreign documents and users without changing a tenant or creating a portfolio' do
    foreign = create(:account)
    foreign_user = create(:user, account: foreign)
    foreign_assignment = JrcRelationship::Assignment.create!(account: foreign, contact: create(:contact, account: foreign))
    foreign_document = JrcRelationship::CustomerDocument.create!(account: foreign, assignment: foreign_assignment, title: 'FOREIGN')
    patch "#{base}/#{document.id}", headers: headers, as: :json, params: { document: values.merge(responsible_id: foreign_user.id) }
    expect(response).to have_http_status(:not_found)
    expect(document.reload.responsible_id).to be_nil
    patch "#{base}/#{foreign_document.id}", headers: headers, as: :json, params: { document: values }
    expect(response).to have_http_status(:not_found)
    get "#{base}/#{foreign_document.id}/responsibles", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(foreign_document.reload.responsible_id).to be_nil
  end

  it 'uses native team eligibility rather than assigning any user in the account' do
    document
    role = create(:custom_role, account: account, permissions: %w[contact_manage jrc_relationship_view jrc_relationship_documents_manage])
    account.account_users.find_by!(user: analyst).update!(custom_role: role)
    auth = analyst.create_new_auth_token
    get "#{base}/#{document.id}/responsibles", headers: auth
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload'].pluck('id')).to eq([analyst.id])
    patch "#{base}/#{document.id}", headers: auth, as: :json, params: { document: values.merge(responsible_id: manager.id) }
    expect(response).to have_http_status(:not_found)
    expect(document.reload.responsible_id).to be_nil
  end

  it 'paginates bounded eligible options and exposes no email or credentials' do
    document
    3.times { |i| create(:user, account: account, name: "Eligible synthetic #{i}") }
    get "#{base}/#{document.id}/responsibles", headers: headers, params: { q: 'Eligible synthetic', page: 2, per_page: 2 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['meta']).to include('page' => 2, 'per_page' => 2, 'total' => 3)
    expect(response.parsed_body['payload'].size).to eq(1)
    expect(response.parsed_body['payload'].first.keys).to match_array(%w[id name eligible])
  end

  it 'requires a bounded reason and valid status and never applies an invalid metadata update' do
    before = document.attributes
    [values.merge(reason: ''), values.merge(status: 'signed'), values.merge(responsible_id: %w[1 2]), values.except(:revision)].each do |body|
      patch "#{base}/#{document.id}", headers: headers, as: :json, params: { document: body }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(document.reload.attributes).to eq(before)
    end
  end
end
