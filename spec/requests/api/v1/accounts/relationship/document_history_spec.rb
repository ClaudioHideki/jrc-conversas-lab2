require 'rails_helper'

RSpec.describe 'Protected native document history', type: :request do
  let(:account) { create(:account) }
  let(:manager) { create(:user, account: account, role: :administrator) }
  let(:reader) { create(:user, account: account, role: :agent) }
  let(:headers) { manager.create_new_auth_token }
  let(:member) { account.account_users.find_by!(user: manager) }
  let(:context) { JrcRelationship::Context.new(member) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: reader) }
  let(:document) do
    JrcRelationship::CustomerDocument.create!(account: account, assignment: assignment, category: 'registration', confidentiality: 'operational',
                                              title: 'SYNTHETIC private history')
  end
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/documents/#{document.id}/history" }
  let(:metadata_event) do
    JrcRelationship::Configuration.create!(account: account, rules: { required_documents: [
                                             { code: 'registration_proof', title: 'SYNTHETIC registration proof', category: 'registration' }
                                           ] })
    attributes = { 'responsible_id' => reader.id, 'status' => 'active', 'requirement_key' => 'registration_proof',
                   'revision' => document.lock_version, 'reason' => 'SYNTHETIC reviewed change' }
    JrcRelationship::DocumentMetadata.new(context).update!(document_id: document.id, attributes: attributes)
    JrcCrm::AuditEvent.where(account: account, resource_type: document.class.name, resource_id: document.id)
                      .find_by!("metadata ->> 'action' = 'document_metadata_updated'")
  end
  let(:version) do
    attributes = { 'change_reason' => 'SYNTHETIC immutable version reason', 'valid_until' => (Date.current + 30).iso8601 }
    file = fixture_file_upload('jrc_projects_task.txt', 'text/plain')
    JrcRelationship::CustomerDocuments.new(context).upload!(assignment_id: assignment.id, document_id: document.id,
                                                            attributes: attributes, upload: file)
    document.versions.order(number: :desc).first!
  end
  let(:version_event) do
    version
    JrcCrm::AuditEvent.where(account: account, resource_type: document.class.name, resource_id: document.id)
                      .find_by!("metadata ->> 'action' = 'document_uploaded'")
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship') }

  it 'projects the recorded before/after responsibility, actor and reason without changing documents or versions' do
    metadata_event
    original = document.reload.attributes
    get url, headers: headers
    expect(response).to have_http_status(:ok)
    row = response.parsed_body['payload'].first
    expect(row).to include('actor' => { 'state' => 'available', 'id' => manager.id, 'name' => manager.name }, 'reason' => 'SYNTHETIC reviewed change')
    expect(row.dig('before', 'responsible')).to eq('state' => 'unassigned')
    expect(row.dig('after', 'responsible')).to include('id' => reader.id, 'name' => reader.name)
    expect(row['after']).to include('status' => 'active', 'requirement_key' => 'registration_proof')
    expect(document.reload.attributes).to eq(original)
    expect(document.versions.count).to eq(0)
  end

  it 'uses the immutable native version reason and excludes download and unrelated audit records' do
    version_event
    context.audit!(document, action: 'document_downloaded')
    get url, headers: headers, params: { kind: 'version' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['meta']['total']).to eq(1)
    expect(response.parsed_body['payload'].first).to include('action' => 'document_uploaded', 'reason' => version.change_reason,
                                                             'version' => { 'id' => version.id, 'number' => 1,
                                                                            'valid_until' => version.valid_until.iso8601 })
    expect(response.body).not_to include('document_downloaded', 'signed_id', 'checksum', 'filename', 'ip_address')
  end

  it 'paginates stable native events and filters actions with a server-enforced upper page size' do
    metadata_event
    version_event
    get url, headers: headers, params: { per_page: 1, page: 2 }
    expect(response.parsed_body['meta']).to include('total' => 2, 'per_page' => 1, 'page' => 2)
    expect(response.parsed_body['payload'].first['id']).to eq(metadata_event.id)
    get url, headers: headers, params: { kind: 'metadata', per_page: 500 }
    expect(response.parsed_body['meta']).to include('total' => 1, 'per_page' => 50)
    get url, headers: headers, params: { kind: 'all_records' }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'permits a native documentary reader and denies access immediately after its grant is revoked' do
    metadata_event
    role = create(:custom_role, account: account, permissions: %w[contact_manage jrc_relationship_view jrc_relationship_documents_view])
    account.account_users.find_by!(user: reader).update!(custom_role: role)
    auth = reader.create_new_auth_token
    get url, headers: auth
    expect(response).to have_http_status(:ok)
    role.update!(permissions: %w[contact_manage jrc_relationship_view])
    get url, headers: auth
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include('SYNTHETIC reviewed change')
  end

  it 'rejects foreign documents and foreign account audit records even if a resource identifier is forged' do
    metadata_event
    foreign = create(:account)
    foreign_assignment = JrcRelationship::Assignment.create!(account: foreign, contact: create(:contact, account: foreign))
    foreign_document = JrcRelationship::CustomerDocument.create!(account: foreign, assignment: foreign_assignment, title: 'FOREIGN')
    JrcCrm::AuditEvent.create!(account: foreign, resource_type: document.class.name, resource_id: document.id,
                               event_type: 'relationship_updated', metadata: { action: 'document_metadata_updated' },
                               to_value: { reason: 'FOREIGN_SECRET' })
    get url, headers: headers
    expect(response.parsed_body['meta']['total']).to eq(1)
    expect(response.body).not_to include('FOREIGN_SECRET')
    get "/api/v1/accounts/#{account.id}/relationship/documents/#{foreign_document.id}/history", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'whitelists fields and hides users outside this account instead of returning raw audit JSON' do
    foreign_user = create(:user, account: create(:account), name: 'FOREIGN PRIVATE NAME')
    JrcCrm::AuditEvent.create!(account: account, actor_type: 'User', actor_id: foreign_user.id, resource_type: document.class.name,
                               resource_id: document.id, event_type: 'relationship_updated',
                               metadata: { action: 'document_metadata_updated', token: 'PRIVATE_TOKEN' },
                               from_value: { responsible_id: foreign_user.id, api_key: 'PRIVATE_KEY' },
                               to_value: { responsible_id: nil, reason: 'SYNTHETIC safe reason', url: 'PRIVATE_URL' })
    get url, headers: headers
    expect(response).to have_http_status(:ok)
    row = response.parsed_body['payload'].first
    expect(response.headers['Cache-Control']).to eq('no-store')
    expect(row['actor']).to eq('state' => 'unavailable')
    expect(row.dig('before', 'responsible')).to eq('state' => 'unavailable')
    expect(row.keys).to match_array(%w[id action at actor before after reason version])
    expect(response.body).not_to include('FOREIGN PRIVATE NAME', 'PRIVATE_TOKEN', 'PRIVATE_KEY', 'PRIVATE_URL', foreign_user.email)
  end

  it 'honors operator and unit coverage for an owned portfolio without creating any access exception' do
    metadata_event
    issuer_a = account.master_companies.create!(name: 'SYNTHETIC operator A', relationship_type: 'internal')
    issuer_b = account.master_companies.create!(name: 'SYNTHETIC operator B', relationship_type: 'internal')
    unit_a = account.jrc_crm_business_units.create!(name: 'SYNTHETIC A', code: 'SYN-A', operating_company: issuer_a)
    unit_b = account.jrc_crm_business_units.create!(name: 'SYNTHETIC B', code: 'SYN-B', operating_company: issuer_b)
    account.jrc_crm_user_business_units.create!(user: reader, company: issuer_a, business_unit: unit_a,
                                                scope: 'BUSINESS_UNIT', structure_managed: true, active: true)
    role = create(:custom_role, account: account, permissions: %w[contact_manage jrc_relationship_view jrc_relationship_documents_view])
    account.account_users.find_by!(user: reader).update!(custom_role: role)
    assignment.update!(business_unit: unit_b)
    auth = reader.create_new_auth_token
    get url, headers: auth
    expect(response).to have_http_status(:not_found)
    assignment.update!(business_unit: unit_a)
    get url, headers: auth
    expect(response).to have_http_status(:ok)
  end
end
