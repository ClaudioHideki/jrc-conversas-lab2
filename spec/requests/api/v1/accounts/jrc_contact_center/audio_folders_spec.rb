require 'rails_helper'

RSpec.describe 'Institutional audio folders stay within the current native operational unit', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let!(:headers) { actor.create_new_auth_token }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC audio issuer', relationship_type: 'internal') }
  let(:business) do
    %w[A B].map { |code| account.jrc_crm_business_units.create!(operating_company: company, code: code, name: "SYNTHETIC #{code}") }
  end
  let(:units) do
    business.map do |row|
      JrcContactCenter::Unit.create!(account: account, code: row.code, name: row.name, kind: 'sac',
                                     settings: { issuer_company_id: company.id, business_unit_id: row.id })
    end
  end
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center/audio_folders" }
  let(:folder) { JrcContactCenter::AudioFolder.create!(account: account, unit: units.first, name: 'SYNTHETIC root') }

  before do
    account.enable_features!('jrc_contact_center', 'audit_logs', 'custom_roles')
    member.update!(custom_role: create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_configure]))
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: company,
                                               business_unit: business.first, active: true, structure_managed: true)
  end

  it 'persists an organizational folder in its real unit without producing an audio, grant or provider command' do
    post base, headers: headers, params: { folder: { unit_id: units.first.id, name: 'SYNTHETIC library' } }, as: :json
    expect(response).to have_http_status(:created)
    item = response.parsed_body.fetch('item')
    expect(item).to include('unit_id' => units.first.id.to_s, 'name' => 'SYNTHETIC library', 'parent_id' => nil)
    expect(item.fetch('revision')).to match(/\A[0-9a-f]{64}\z/)
    expect(JrcContactCenter::AudioFolder.find(item.fetch('id')).account_id).to eq(account.id)
    expect(JrcContactCenter::AccessGrant.where(account: account).count).to eq(1)
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  it 'does not expose another operational unit or foreign account through list, details, parent or create' do
    hidden = JrcContactCenter::AudioFolder.create!(account: account, unit: units.last, name: 'SYNTHETIC denied')
    get base, headers: headers, params: { unit_id: units.last.id }
    expect(response).to have_http_status(:not_found)
    get "#{base}/#{hidden.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    post base, headers: headers, params: { folder: { unit_id: units.last.id, name: 'SYNTHETIC denied create' } }, as: :json
    expect(response).to have_http_status(:not_found)
    post base, headers: headers, params: { folder: { unit_id: units.first.id, parent_id: hidden.id, name: 'SYNTHETIC denied parent' } }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(JrcContactCenter::AudioFolder.where(account: account).pluck(:id)).to eq([hidden.id])
  end

  it 'paginates the selected native unit and keeps search and hierarchy explicit' do
    root = folder
    JrcContactCenter::AudioFolder.create!(account: account, unit: units.first, parent: root, name: 'SYNTHETIC child')
    JrcContactCenter::AudioFolder.create!(account: account, unit: units.first, name: 'SYNTHETIC other root')
    get base, headers: headers, params: { unit_id: units.first.id, parent_id: '', per_page: 1, page: 2 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').length).to eq(1)
    expect(response.parsed_body.fetch('meta')).to include('total' => 2, 'pages' => 2, 'page' => 2)
    get base, headers: headers, params: { unit_id: units.first.id, parent_id: root.id, q: 'child' }
    expect(response.parsed_body.fetch('items').pluck('name')).to eq(['SYNTHETIC child'])
  end

  it 'edits with a native revision and rejects a stale retry without changing identity or unit' do
    expected = JrcContactCenter::ConfigurationRevision.token(folder)
    patch "#{base}/#{folder.id}", headers: headers,
                                  params: { folder: { name: 'SYNTHETIC renamed' }, expected_revision: expected }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item')).to include('id' => folder.id.to_s, 'unit_id' => units.first.id.to_s)
    patch "#{base}/#{folder.id}", headers: headers,
                                  params: { folder: { name: 'SYNTHETIC stale' }, expected_revision: expected }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(folder.reload.name).to eq('SYNTHETIC renamed')
  end

  it 'blocks a parent cycle instead of reorganizing an ancestor under its descendant' do
    child = JrcContactCenter::AudioFolder.create!(account: account, unit: units.first, parent: folder, name: 'SYNTHETIC child')
    expected = JrcContactCenter::ConfigurationRevision.token(folder)
    patch "#{base}/#{folder.id}", headers: headers,
                                  params: { folder: { parent_id: child.id }, expected_revision: expected }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(folder.reload.parent_id).to be_nil
    expect(child.reload.parent_id).to eq(folder.id)
  end

  it 'does not accept an update without its reviewed revision as a legacy unconditional write' do
    original = folder.name
    patch "#{base}/#{folder.id}", headers: headers, params: { folder: { name: 'SYNTHETIC unreviewed' } }, as: :json
    expect(response).to have_http_status(:precondition_required)
    expect(response.parsed_body.fetch('error')).to eq('configuration_revision_required')
    expect(folder.reload.name).to eq(original)
  end

  it 'preserves the exact folder identity when reorganizing within the same authorized unit' do
    destination = JrcContactCenter::AudioFolder.create!(account: account, unit: units.first, name: 'SYNTHETIC destination')
    expected = JrcContactCenter::ConfigurationRevision.token(folder)
    patch "#{base}/#{folder.id}", headers: headers,
                                  params: { folder: { parent_id: destination.id }, expected_revision: expected }, as: :json
    expect(response).to have_http_status(:ok)
    expect(folder.reload).to have_attributes(parent_id: destination.id, unit_id: units.first.id)
  end

  it 'does not permit an implicit cross-unit move or caller-provided account' do
    expected = JrcContactCenter::ConfigurationRevision.token(folder)
    patch "#{base}/#{folder.id}", headers: headers,
                                  params: { folder: { unit_id: units.last.id }, expected_revision: expected }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post base, headers: headers, params: { folder: { account_id: create(:account).id, unit_id: units.first.id, name: 'SYNTHETIC forged' } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(folder.reload.unit_id).to eq(units.first.id)
  end

  it 'does not create duplicate siblings on repeated uncertain submissions or case changes' do
    post base, headers: headers, params: { folder: { unit_id: units.first.id, name: 'SYNTHETIC repeat' } }, as: :json
    expect(response).to have_http_status(:created)
    post base, headers: headers, params: { folder: { unit_id: units.first.id, name: 'synthetic REPEAT' } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::AudioFolder.where(account: account).count).to eq(1)
  end

  it 'rolls back metadata and revision if mandatory audit fails' do
    expected = JrcContactCenter::ConfigurationRevision.token(folder)
    allow(JrcContactCenter::ConfigurationAudit).to receive(:write!).and_wrap_original do |_original, record, **_values|
      raise ActiveRecord::RecordInvalid, record
    end
    patch "#{base}/#{folder.id}", headers: headers,
                                  params: { folder: { name: 'SYNTHETIC unaudited' }, expected_revision: expected }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::ConfigurationRevision.token(folder.reload)).to eq(expected)
  end

  it 'records current actor, unit and correlation using the existing scoped audit' do
    post base, headers: headers, params: { folder: { unit_id: units.first.id, name: 'SYNTHETIC audited' } }, as: :json
    expect(response).to have_http_status(:created)
    row = Audited.audit_class.where(auditable_type: 'JrcContactCenter::AudioFolder', associated: account).last
    expect(row.user_id).to eq(actor.id)
    expect(row.request_uuid).to be_present
    expect(row.audited_changes.dig('cc_scope', 'after', 'unit_id')).to eq(units.first.id.to_s)
    expect(row.audited_changes.to_json).not_to include('signed_id', 'service_url', 'rails_blob_url')
  end

  it 'does not accept recordings-only authority as institutional audio management' do
    member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_recordings_view jrc_contact_center_recordings_listen])
    get base, headers: headers, params: { unit_id: units.first.id }
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::AudioFolder.where(account: account)).to be_empty
  end

  it 'exposes the authorized folder audit history but rejects another unit detail and history' do
    member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_configure jrc_contact_center_audit])
    hidden = JrcContactCenter::AudioFolder.create!(account: account, unit: units.last, name: 'SYNTHETIC hidden audit')
    hidden_audit = Audited.audit_class.where(auditable: hidden, associated: account).last
    own = folder
    endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/configuration_audits"
    get endpoint, headers: headers, params: { resource_type: 'audio_folder', resource_id: own.id.to_s, history: 'true' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to include(hash_including('resource_type' => 'audio_folder', 'resource_id' => own.id))
    get "#{endpoint}/#{hidden_audit.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    get endpoint, headers: headers, params: { resource_type: 'audio_folder', resource_id: hidden.id.to_s, history: 'true' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to be_empty
  end

  [[], {}, false, '1invalid'].each do |invalid|
    it "rejects malformed parent #{invalid.inspect} instead of silently creating a root" do
      post base, headers: headers, params: { folder: { unit_id: units.first.id, parent_id: invalid, name: 'SYNTHETIC malformed' } }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JrcContactCenter::AudioFolder.where(account: account)).to be_empty
    end
  end

  it 'does not read a foreign folder identity through the current account path' do
    other = create(:account)
    hidden_unit = JrcContactCenter::Unit.create!(account: other, code: 'OTHER', name: 'SYNTHETIC foreign unit', kind: 'sac')
    hidden = JrcContactCenter::AudioFolder.create!(account: other, unit: hidden_unit, name: 'SYNTHETIC foreign folder')
    get "#{base}/#{hidden.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(hidden.name)
    expect(JrcContactCenter::AudioFolder.where(account: account)).to be_empty
  end
end
