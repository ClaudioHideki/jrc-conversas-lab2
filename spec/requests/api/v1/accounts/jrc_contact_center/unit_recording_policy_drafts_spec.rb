# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Native unit recording policy drafts retain authorization, revision and audit', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let!(:headers) { actor.create_new_auth_token }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC recording issuer', relationship_type: 'internal') }
  let(:business) do
    %w[A B].map { |code| account.jrc_crm_business_units.create!(operating_company: company, code: code, name: "SYNTHETIC #{code}") }
  end
  let(:units) do
    business.map do |row|
      JrcContactCenter::Unit.create!(account: account, code: row.code, name: row.name, kind: 'sac',
                                     settings: { issuer_company_id: company.id, business_unit_id: row.id, unrelated: 'preserve' })
    end
  end
  let(:unit) { units.first }
  let(:key) { JrcContactCenter::RecordingPolicyDraft::KEY }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center/unit_recording_policy_drafts" }
  let(:path) { "#{base}/#{unit.id}" }
  let(:definition) do
    queue = JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'SYNTHETIC-Q', name: 'SYNTHETIC queue')
    { 'mode' => 'on_demand', 'queue_scope' => 'selected_queues', 'queue_ids' => [queue.id.to_s],
      'notice' => 'SYNTHETIC private customer notice', 'retention_days' => nil }
  end
  let(:stored) { JrcContactCenter::RecordingPolicyDraft.build(unit: unit, values: definition) }
  let(:body) { { recording_policy_draft: definition, expected_revision: JrcContactCenter::ConfigurationRevision.token(unit.reload) } }

  before do
    account.enable_features!('jrc_contact_center', 'audit_logs', 'custom_roles')
    member.update!(custom_role: create(:custom_role, account: account,
                                                     permissions: %w[jrc_contact_center_view jrc_contact_center_configure jrc_contact_center_audit]))
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: company,
                                                business_unit: business.first, active: true, structure_managed: true)
  end

  it 'reads an unconfigured unit without inventing or persisting a recording policy' do
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('account_id' => account.id.to_s, 'unit_id' => unit.id.to_s, 'draft' => nil,
                                            'applied' => false, 'provider_state' => 'not_verified')
    expect(response.headers['Cache-Control']).to eq('private, no-store')
    expect(unit.reload.settings).not_to have_key(key)
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  it 'saves and reloads the reviewed draft with native redacted before and after audit' do
    patch path, headers: headers, params: body, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('draft')).to eq(stored)
    get path, headers: headers
    expect(response.parsed_body.fetch('draft')).to eq(unit.reload.settings.fetch(key))
    audit = Audited.audit_class.where(auditable: unit, action: 'update').last
    expect([audit.user_id, audit.request_uuid.present?]).to eq([actor.id, true])
    expect(audit.audited_changes.dig('attributes', 1, 'settings', key)).to include('notice_sha256' => Digest::SHA256.hexdigest(definition['notice']))
    expect(audit.audited_changes.to_json).not_to include(definition.fetch('notice'))
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  it 'binds the stored draft to the exact native account, unit and corporate sources' do
    patch path, headers: headers, params: body, as: :json
    expect(response).to have_http_status(:ok)
    snapshot = unit.reload.settings.fetch(key).fetch('scope_snapshot')
    expect(snapshot).to eq('account_id' => account.id.to_s, 'unit_id' => unit.id.to_s,
                           'issuer_company_id' => company.id.to_s, 'business_unit_id' => business.first.id.to_s)
  end

  it 'rejects silent corporate reassignment of a unit that contains a reviewed recording draft' do
    patch path, headers: headers, params: body, as: :json
    other_scope = unit.reload.settings.merge('business_unit_id' => business.last.id)
    expect(unit.update(settings: other_scope)).to be(false)
    expect(unit.reload.settings.fetch(key)).to eq(stored)
    expect(unit.settings.fetch('business_unit_id').to_s).to eq(business.first.id.to_s)
  end

  it 'preserves unrelated settings and rejects stale changes without a second write or audit' do
    input = body
    patch path, headers: headers, params: input, as: :json
    audit_count = Audited.audit_class.where(auditable: unit).count
    patch path, headers: headers, params: input.merge(recording_policy_draft: definition.merge('notice' => 'SYNTHETIC stale')), as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('stale_configuration_revision')
    expect(unit.reload.settings).to include('unrelated' => 'preserve', key => stored)
    expect(Audited.audit_class.where(auditable: unit).count).to eq(audit_count)
  end

  it 'requires the existing native revision even for a first policy save' do
    patch path, headers: headers, params: body.except(:expected_revision), as: :json
    expect(response).to have_http_status(:precondition_required)
    expect(response.parsed_body.fetch('error')).to eq('configuration_revision_required')
    expect(unit.reload.settings).not_to have_key(key)
  end

  it 'rejects both reading and writing another corporate unit in the same account' do
    input = body
    get "#{base}/#{units.last.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    patch "#{base}/#{units.last.id}", headers: headers, params: input, as: :json
    expect(response).to have_http_status(:not_found)
    expect(units.last.reload.settings).not_to have_key(key)
  end

  it 'rejects a foreign account unit without exposing its name or draft' do
    hidden = JrcContactCenter::Unit.create!(account: create(:account), code: 'SECRET', name: 'SYNTHETIC foreign secret', kind: 'sac')
    get "#{base}/#{hidden.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(hidden.name)
    patch "#{base}/#{hidden.id}", headers: headers, params: body, as: :json
    expect(response).to have_http_status(:not_found)
    expect(hidden.reload.settings).not_to have_key(key)
  end

  it 'rejects queue identifiers from another unit despite access to the selected unit' do
    hidden = JrcContactCenter::Queue.create!(account: account, unit: units.last, code: 'HIDDEN', name: 'SYNTHETIC private queue')
    input = body.merge(recording_policy_draft: definition.merge('queue_ids' => [hidden.id.to_s]))
    patch path, headers: headers, params: input, as: :json
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(hidden.name)
    expect(unit.reload.settings).not_to have_key(key)
  end

  it 'reauthorizes current configuration rights without treating recording access as administration' do
    input = body
    member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_recordings_view])
    get path, headers: headers
    expect(response).to have_http_status(:unauthorized)
    patch path, headers: headers, params: input, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(unit.reload.settings).not_to have_key(key)
  end

  it 'does not accept body identifiers as account or unit grants' do
    patch path, headers: headers, params: body.merge(account_id: account.id, unit_id: units.last.id), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(unit.reload.settings).not_to have_key(key)
    expect(units.last.reload.settings).not_to have_key(key)
  end

  [false, [], { 'mode' => 'automatic' }].each do |value|
    it "rejects malformed policy #{value.inspect} without silently treating it as absent" do
      patch path, headers: headers, params: body.merge(recording_policy_draft: value), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(unit.reload.settings).not_to have_key(key)
    end
  end

  it 'does not expose the private notice through the existing generic unit list or generic update' do
    patch path, headers: headers, params: body, as: :json
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/units", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(definition.fetch('notice'), key)
    patch(
      "/api/v1/accounts/#{account.id}/jrc_contact_center/units/#{unit.id}",
      headers: headers, params: { unit: { settings: { key => definition } } }, as: :json
    )
    expect(response).to have_http_status(:unprocessable_entity)
    expect(unit.reload.settings.fetch(key)).to eq(stored)
  end

  it 'rejects removal and malformed direct model writes while preserving the last valid draft' do
    patch path, headers: headers, params: body, as: :json
    expect(unit.reload.update(settings: unit.settings.except(key))).to be(false)
    unit.reload
    expect(unit.update(settings: unit.settings.merge(key => false))).to be(false)
    expect(unit.reload.settings.fetch(key)).to eq(stored)
  end
end
