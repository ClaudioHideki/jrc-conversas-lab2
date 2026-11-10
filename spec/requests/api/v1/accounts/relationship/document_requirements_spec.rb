require 'rails_helper'

RSpec.describe 'Native versioned required document catalog', type: :request do
  let(:account) { create(:account) }
  let(:manager) { create(:user, account: account, role: :administrator) }
  let(:analyst) { create(:user, account: account, role: :agent) }
  let(:headers) { manager.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship/documents" }
  let(:config_url) { "/api/v1/accounts/#{account.id}/relationship/configuration" }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: analyst) }
  let(:entry) { { 'code' => 'registration_proof', 'title' => 'SYNTHETIC registration evidence', 'category' => 'registration' } }
  let(:configuration) { JrcRelationship::Configuration.create!(account: account, rules: { 'required_documents' => [entry] }) }
  let(:upload) { fixture_file_upload('jrc_projects_task.txt', 'text/plain') }
  let(:attributes) { { title: 'SYNTHETIC evidence', category: 'registration', confidentiality: 'operational', requirement_key: entry['code'], change_reason: 'Synthetic upload' } }
  let(:document) do
    configuration
    post base, headers: headers, params: { assignment_id: assignment.id, document: attributes, file: upload }
    JrcRelationship::CustomerDocument.find(response.parsed_body.fetch('id'))
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship') }

  it 'versions catalogs using existing configuration history and rejects stale saves' do
    get config_url, headers: headers, as: :json
    original = response.parsed_body.slice('scope_key', 'version', 'weights', 'rules')
    change = original.merge('rules' => original['rules'].merge('required_documents' => [entry]))
    patch config_url, headers: headers, as: :json, params: change
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['history'].map { |row| row.dig('rules', 'required_documents') }).to eq([[entry], []])
    patch config_url, headers: headers, as: :json, params: change
    expect(response).to have_http_status(:conflict)
    expect(JrcRelationship::Configuration.find_by!(account: account).rules['required_documents']).to eq([entry])
  end

  it 'rejects malformed or duplicate catalog definitions without changing the current version' do
    configuration
    original = { scope_key: 'account', version: 1, weights: configuration.effective_weights }
    [[entry, entry], [entry.merge('code' => 'UPPER')], [entry.merge('category' => 'signed')],
     [entry.merge('title' => '')], [entry.merge('approval' => true)], 'not-a-catalog'].each do |catalog|
      patch config_url, headers: headers, as: :json, params: original.merge(rules: { required_documents: catalog })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(configuration.reload).to have_attributes(version: 1, rules: { 'required_documents' => [entry] })
    end
  end

  it 'uses independent configuration and documentary grants' do
    role = create(:custom_role, account: account, permissions: %w[contact_manage jrc_relationship_view jrc_relationship_documents_manage])
    account.account_users.find_by!(user: analyst).update!(custom_role: role)
    auth = analyst.create_new_auth_token
    get config_url, headers: auth
    expect(response).to have_http_status(:forbidden)
    role.update!(permissions: %w[contact_manage jrc_relationship_view jrc_relationship_configure])
    get base, headers: auth, params: { assignment_id: assignment.id }
    expect(response).to have_http_status(:forbidden)
  end

  it 'projects the catalog selected by the existing company configuration precedence' do
    configuration
    company = account.master_companies.create!(name: 'SYNTHETIC configured customer')
    assignment.update!(company: company, contact: nil)
    customer_entry = entry.merge('code' => 'customer_specific', 'title' => 'Customer-specific evidence')
    JrcRelationship::Configuration.create!(account: account, scope_key: "company:#{company.id}",
                                           rules: { required_documents: [customer_entry] })
    get base, headers: headers, params: { assignment_id: assignment.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['requirements']).to include('scope_key' => "company:#{company.id}", 'configuration_version' => 1)
    expect(response.parsed_body.dig('requirements', 'entries').pluck('code')).to eq(['customer_specific'])
  end

  it 'does not infer a requirement link from a matching title or category' do
    configuration
    post base, headers: headers, params: { assignment_id: assignment.id, document: attributes.except(:requirement_key), file: upload }
    expect(response).to have_http_status(:created)
    expect(response.parsed_body['requirement_key']).to be_nil
    get base, headers: headers, params: { assignment_id: assignment.id }
    expect(response.parsed_body.dig('requirements', 'entries', 0)).to include('state' => 'missing', 'document_id' => nil)
  end

  it 'preserves exact file versions and marks the latest unscanned or expired evidence without legal approval' do
    version = document.versions.first!
    blob = version.file.blob
    # Simulated scanner attestation, solely for this automated test; not external antivirus homologation.
    blob.update!(metadata: { 'service_desk_scan_state' => 'clean', 'service_desk_scan_adapter' => 'clamav-instream-v1',
                             'service_desk_scan_sha256' => Digest::SHA256.hexdigest(blob.download),
                             'service_desk_scanned_at' => Time.current.iso8601 })
    get base, headers: headers, params: { assignment_id: assignment.id }
    expect(response.parsed_body.dig('requirements', 'entries', 0)).to include('state' => 'file_available', 'version_id' => version.id)
    post "#{base}/#{document.id}/version", headers: headers,
                                           params: { assignment_id: assignment.id, file: upload,
                                                     document: { change_reason: 'New evidence under review' } }
    get base, headers: headers, params: { assignment_id: assignment.id }
    expect(response.parsed_body.dig('requirements', 'entries', 0)).to include('state' => 'quarantined', 'version_number' => 2)
    post "#{base}/#{document.id}/version", headers: headers,
                                           params: { assignment_id: assignment.id, file: upload,
                                                     document: { change_reason: 'Expired replacement evidence',
                                                                 valid_until: 2.days.ago.to_date.iso8601 } }
    get base, headers: headers, params: { assignment_id: assignment.id }
    expect(response.parsed_body.dig('requirements', 'entries', 0)).to include('state' => 'expired', 'version_number' => 3)
    expect(version.reload.file.blob.id).to eq(blob.id)
    expect(document.versions.count).to eq(3)
    expect(response.parsed_body.dig('requirements', 'entries', 0).keys).not_to include('approved', 'signing_authority', 'url', 'key')
  end

  it 'rejects unknown or incompatible requirements before persisting a document or file version' do
    configuration
    [attributes.merge(requirement_key: 'unknown'), attributes.merge(category: 'contract')].each do |invalid|
      post base, headers: headers, params: { assignment_id: assignment.id, document: invalid, file: upload }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JrcRelationship::CustomerDocument.where(account: account).count).to eq(0)
    end
  end

  it 'links legacy evidence only by an explicit audited metadata change' do
    configuration
    post base, headers: headers, params: { assignment_id: assignment.id, document: attributes.except(:requirement_key), file: upload }
    legacy = JrcRelationship::CustomerDocument.find(response.parsed_body.fetch('id'))
    patch "#{base}/#{legacy.id}", headers: headers, as: :json,
                                  params: { document: { requirement_key: entry['code'], revision: 0, reason: 'Explicit evidence mapping' } }
    expect(response).to have_http_status(:ok)
    expect(legacy.reload.requirement_key).to eq(entry['code'])
    expect(legacy.versions.count).to eq(1)
    event = JrcCrm::AuditEvent.where(account: account, resource_type: legacy.class.name, resource_id: legacy.id)
                              .find_by!("metadata ->> 'action' = 'document_metadata_updated'")
    expect(event.to_value).to include('requirement_key' => entry['code'], 'reason' => 'Explicit evidence mapping')
  end

  it 'preserves links and file history when configuration removes an obligation' do
    version_id = document.versions.first!.id
    get config_url, headers: headers, as: :json
    current = response.parsed_body.slice('scope_key', 'version', 'weights', 'rules')
    patch config_url, headers: headers, as: :json, params: current.merge('rules' => current['rules'].merge('required_documents' => []))
    expect(response).to have_http_status(:ok)
    get base, headers: headers, params: { assignment_id: assignment.id }
    expect(response.parsed_body.dig('requirements', 'entries')).to eq([])
    expect(document.reload.requirement_key).to eq(entry['code'])
    expect(document.versions.first!.id).to eq(version_id)
  end

  it 'allows one active evidence per requirement while retaining archived evidence and versions' do
    old_id = document.id
    post base, headers: headers, params: { assignment_id: assignment.id, document: attributes, file: upload }
    expect(response).to have_http_status(:conflict)
    patch "#{base}/#{old_id}", headers: headers, as: :json,
                               params: { document: { status: 'archived', revision: 0, reason: 'Replace evidence without deleting history' } }
    expect(response).to have_http_status(:ok)
    post base, headers: headers, params: { assignment_id: assignment.id, document: attributes, file: upload }
    expect(response).to have_http_status(:created)
    expect(response.parsed_body['id']).not_to eq(old_id)
    expect(document.reload.versions.count).to eq(1)
  end

  it 'does not expose a foreign catalog or create an assignment for a denied company' do
    foreign = create(:account)
    company = foreign.master_companies.create!(name: 'FOREIGN synthetic company')
    foreign_assignment = JrcRelationship::Assignment.create!(account: foreign, company: company)
    JrcRelationship::Configuration.create!(account: foreign, rules: { required_documents: [entry.merge('title' => 'FOREIGN required file')] })
    get base, headers: headers, params: { assignment_id: foreign_assignment.id }
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('FOREIGN required file')
    expect(JrcRelationship::Assignment.where(account: account).count).to eq(0)
    get config_url, headers: headers, params: { scope_key: "company:#{company.id}" }
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
