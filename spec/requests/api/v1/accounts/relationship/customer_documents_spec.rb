require 'rails_helper'

RSpec.describe 'Protected Relationship customer documents', type: :request do
  let(:account) { create(:account) }
  let(:manager) { create(:user, account: account, role: :administrator) }
  let(:analyst) { create(:user, account: account, role: :agent) }
  let(:headers) { manager.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/documents" }
  let!(:assignment) { JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: analyst) }
  let(:file) { fixture_file_upload('jrc_projects_task.txt', 'text/plain') }
  let(:attributes) { { title: 'SYNTHETIC registration evidence', category: 'registration', change_reason: 'Initial synthetic upload' } }
  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'preserves previous versions, quarantines unscanned content and never returns a bearer storage URL' do
    post url, headers: headers, params: { assignment_id: assignment.id, document: attributes, file: file }
    expect(response).to have_http_status(:created)
    document_id = response.parsed_body.fetch('id')
    first = response.parsed_body.fetch('versions').first
    expect(first).to include('number' => 1, 'download_available' => false,
                             'uploaded_by' => { 'id' => manager.id, 'name' => manager.name })
    expect(response.parsed_body).to include('status' => 'active', 'portfolio_owner' => { 'id' => analyst.id, 'name' => analyst.name })
    expect(first['uploaded_by'].keys).to match_array(%w[id name])
    expect(first.keys).not_to include('url', 'signed_id', 'key')
    get "#{url}/#{document_id}/versions/#{first['id']}/download", headers: headers
    expect(response).to have_http_status(:conflict)
    post "#{url}/#{document_id}/version", headers: headers,
      params: { assignment_id: assignment.id, document: { change_reason: 'Updated evidence', valid_until: Date.yesterday.iso8601 }, file: file }
    expect(response).to have_http_status(:created)
    expect(response.parsed_body['versions'].pluck('number')).to eq([2, 1])
    expect(response.parsed_body['versions'].first['expired']).to be(true)
    expect(JrcRelationship::DocumentVersion.find(first['id']).file).to be_attached
  end

  it 'denies generic Active Storage redirect, proxy, representation and disk bearer routes' do
    post url, headers: headers, params: { assignment_id: assignment.id, document: attributes, file: file }
    version = JrcRelationship::CustomerDocument.find(response.parsed_body.fetch('id')).versions.first!
    blob = version.file.blob
    expect(ActiveStorage::Blobs::RedirectController._process_action_callbacks.map(&:filter)).to include(:deny_relationship_document_blob)
    expect(blob.attachments.pluck(:record_type)).to include(JrcRelationship::DocumentVersion.polymorphic_name)
    get rails_storage_redirect_path(blob), headers: headers
    expect(response).to have_http_status(:not_found), "route keys=#{request.path_parameters.keys}; redirect scheme=#{URI(response.location.to_s).scheme}"
    get rails_storage_proxy_path(blob), headers: headers
    expect(response).to have_http_status(:not_found)
    variation = ActiveStorage::Variation.wrap(resize_to_limit: [100, 100]).key
    get rails_blob_representation_proxy_path(variation_key: variation, signed_blob_id: blob.signed_id, filename: blob.filename), headers: headers
    expect(response).to have_http_status(:not_found)
    get rails_blob_representation_path(variation_key: variation, signed_blob_id: blob.signed_id, filename: blob.filename), headers: headers
    expect(response).to have_http_status(:not_found)
    key = ActiveStorage.verifier.generate({ key: blob.key, disposition: 'attachment', content_type: blob.content_type,
                                          service_name: blob.service_name }, purpose: :blob_key)
    get rails_disk_service_path(encoded_key: key, filename: blob.filename), headers: headers
    expect(response).to have_http_status(:not_found)
    upload_key = ActiveStorage.verifier.generate({ key: blob.key, content_type: blob.content_type, content_length: blob.byte_size,
                                                  checksum: blob.checksum, service_name: blob.service_name }, purpose: :blob_token)
    put update_rails_disk_service_path(encoded_token: upload_key), headers: headers, params: 'replace'
    expect(response).to have_http_status(:not_found)
    ordinary = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('Other native attachment'), filename: 'ordinary.txt', content_type: 'text/plain')
    get rails_storage_redirect_path(ordinary), headers: headers
    expect(response).to have_http_status(:found)
  end

  it 'does not inherit document rights from Backoffice, CRM, Service Desk or a legacy analyst role' do
    analyst_headers = analyst.create_new_auth_token
    get url, headers: analyst_headers, params: { assignment_id: assignment.id }
    expect(response).to have_http_status(:forbidden)
    expect do
      post url, headers: analyst_headers, params: { assignment_id: assignment.id, document: attributes, file: file }
    end.not_to change(JrcRelationship::CustomerDocument, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it 'revalidates scope and custom role on every download and rejects a modified file hash' do
    post url, headers: headers, params: { assignment_id: assignment.id, document: attributes, file: file }
    document = JrcRelationship::CustomerDocument.find(response.parsed_body.fetch('id'))
    version = document.versions.first!
    blob = version.file.blob
    blob.update!(metadata: blob.metadata.merge('service_desk_scan_state' => 'clean', 'service_desk_scan_adapter' => 'clamav-instream-v1',
                                               'service_desk_scanned_at' => Time.current.iso8601, 'service_desk_scan_sha256' => Digest::SHA256.hexdigest(blob.download)))
    role = CustomRole.create!(account: account, name: 'SYNTHETIC document reader',
                               permissions: %w[contact_manage jrc_relationship_view jrc_relationship_documents_view])
    account.account_users.find_by!(user: analyst).update!(custom_role: role)
    analyst_headers = analyst.create_new_auth_token
    get "#{url}/#{document.id}/versions/#{version.id}/download", headers: analyst_headers
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to eq('no-store')
    role.update!(permissions: %w[contact_manage jrc_relationship_view])
    get "#{url}/#{document.id}/versions/#{version.id}/download", headers: analyst_headers
    expect(response).to have_http_status(:forbidden)
    blob.update!(metadata: blob.metadata.merge('service_desk_scan_sha256' => '0' * 64))
    get "#{url}/#{document.id}/versions/#{version.id}/download", headers: headers
    expect(response).to have_http_status(:conflict)
    expect(JrcCrm::AuditEvent.where(account: account, resource_type: document.class.name, resource_id: document.id)
                           .where("metadata ->> 'action' = 'document_downloaded'").count).to eq(1)
  end

  it 'cannot address a document or upload into another account' do
    foreign = create(:account)
    foreign_assignment = JrcRelationship::Assignment.create!(account: foreign, contact: create(:contact, account: foreign))
    foreign_document = JrcRelationship::CustomerDocument.create!(account: foreign, assignment: foreign_assignment, title: 'Private')
    get "#{url}/#{foreign_document.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    post url, headers: headers, params: { assignment_id: foreign_assignment.id, document: attributes, file: file }
    expect(response).to have_http_status(:not_found)
  end

  it 'revalidates operator and business-unit coverage even when the document belongs to the analyst own portfolio' do
    post url, headers: headers, params: { assignment_id: assignment.id, document: attributes, file: file }
    document_id = response.parsed_body.fetch('id')
    issuer_a = account.master_companies.create!(name: 'SYNTHETIC operator A', relationship_type: 'internal')
    issuer_b = account.master_companies.create!(name: 'SYNTHETIC operator B', relationship_type: 'internal')
    unit_a = account.jrc_crm_business_units.create!(name: 'SYNTHETIC A', code: 'SYN-A', operating_company: issuer_a)
    unit_b = account.jrc_crm_business_units.create!(name: 'SYNTHETIC B', code: 'SYN-B', operating_company: issuer_b)
    coverage = account.jrc_crm_user_business_units.create!(user: analyst, company: issuer_a, business_unit: unit_a,
                                                          scope: 'BUSINESS_UNIT', structure_managed: true, active: true)
    role = CustomRole.create!(account: account, name: 'SYNTHETIC scoped document reader',
                               permissions: %w[contact_manage jrc_relationship_view jrc_relationship_documents_view])
    account.account_users.find_by!(user: analyst).update!(custom_role: role)
    assignment.update!(business_unit: unit_b)
    analyst_headers = analyst.create_new_auth_token
    get "#{url}/#{document_id}", headers: analyst_headers
    expect(response).to have_http_status(:not_found)
    assignment.update!(business_unit: unit_a)
    get "#{url}/#{document_id}", headers: analyst_headers
    expect(response).to have_http_status(:ok)
    coverage.update!(company: issuer_b, business_unit: unit_b)
    get "#{url}/#{document_id}", headers: analyst_headers
    expect(response).to have_http_status(:not_found)
  end
end
