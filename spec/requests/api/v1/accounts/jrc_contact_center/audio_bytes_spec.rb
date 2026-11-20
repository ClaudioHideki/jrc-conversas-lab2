require 'rails_helper'

# Positive observations use the owned real ClamAV/FFmpeg tools; the signature DB is synthetic, not malware coverage.
RSpec.describe 'Institutional audio byte access uses current native authority and exact integrity', type: :request do
  include_context 'with an institutional audio receipt'

  let(:headers) { actor.create_new_auth_token }
  let(:access) { JrcContactCenter::AudioLibraryAccess.new(context: context) }
  let(:version) do
    legacy = JrcContactCenter::SyntheticLegacyAudioReceipt.new(access: access)
    legacy.create!(unit_id: unit.id, attributes: { name: 'SYNTHETIC byte access' }, file: upload, key: key)
  end
  let(:proof) do
    JrcContactCenter::AudioInspections.new(access: access)
                                      .create!(asset_id: version.audio_asset_id, version_id: version.id, key: 'synthetic-byte-inspection-001')
  end
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center/audio_assets" }
  let(:endpoint) { "#{base}/#{version.audio_asset_id}/versions/#{version.id}/bytes" }

  before do
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted'
    owned &&= ENV.fetch('JRC_CC_AUDIO_CLAMAV_SOCKET', '').start_with?('/run/jrc-cc-audio-')
    raise 'Only the owned synthetic native audio test resources may be used' unless owned
  end

  it 'does not release a merely quarantined receipt or treat request parameters as proof' do
    get endpoint, headers: headers, params: { ready: true, sha256: version.sha256, user_id: actor.id, unit_id: unit.id }
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('institutional_audio_not_verified')
    expect(response.body).not_to include(bytes, version.blob.key, version.blob.signed_id)
    expect(response.headers['Cache-Control']).to eq('no-store')
  end

  it 'returns exact rehashed bytes with the immutable observation identity and no shared cache or storage redirect' do
    current = proof
    expect(current.ready?).to be(true)
    get endpoint, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body.b).to eq(bytes)
    identities = %w[X-JRC-Audio-Account X-JRC-Audio-Unit X-JRC-Audio-Version X-JRC-Audio-Inspection].index_with { |name| response.headers[name] }
    expect(identities).to eq(
      'X-JRC-Audio-Account' => account.id.to_s, 'X-JRC-Audio-Unit' => unit.id.to_s,
      'X-JRC-Audio-Version' => version.id.to_s, 'X-JRC-Audio-Inspection' => current.id.to_s
    )
    protections = %w[Cache-Control X-Content-Type-Options X-JRC-Audio-SHA256].index_with { |name| response.headers[name] }
    expect(protections).to eq(
      'Cache-Control' => 'no-store', 'X-Content-Type-Options' => 'nosniff', 'X-JRC-Audio-SHA256' => Digest::SHA256.hexdigest(bytes)
    )
    expect(response.media_type).to eq('audio/wav')
    expect(response.headers['Location']).to be_nil
  end

  it 'does not fallback to a previous clean receipt after an unavailable inspection' do
    expect(proof.ready?).to be(true)
    with_modified_env JRC_CC_AUDIO_CLAMAV_SOCKET: nil do
      JrcContactCenter::AudioInspections.new(access: access)
                                        .create!(asset_id: version.audio_asset_id, version_id: version.id, key: 'synthetic-byte-inspection-002')
    end
    get endpoint, headers: headers
    expect(response).to have_http_status(:conflict)
    expect(response.body).not_to include(bytes)
  end

  it 'rejects a different unit even when supplied with a genuine inspected version ID' do
    expect(proof.ready?).to be(true)
    hidden = JrcContactCenter::AudioAsset.create!(account: account, unit: units.last, name: 'SYNTHETIC hidden audio')
    get "#{base}/#{hidden.id}/versions/#{version.id}/bytes", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(bytes, hidden.name)
  end

  it 'does not grant a foreign account or a missing session access to inspected bytes' do
    expect(proof.ready?).to be(true)
    other = create(:account)
    foreign = create(:user, account: other)
    get endpoint, headers: foreign.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(bytes)
    get endpoint
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(bytes)
  end

  it 'rechecks permission on every request without reusing recording-listen permission' do
    expect(proof.ready?).to be(true)
    get endpoint, headers: headers
    expect(response).to have_http_status(:ok)
    member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_recordings_listen])
    get endpoint, headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(bytes)
    expect(response.headers['Cache-Control']).to eq('no-store')
  end

  it 'does not emit even a partial byte response when native storage integrity changed after inspection' do
    expect(proof.ready?).to be(true)
    version.blob.service.upload(version.blob.key, StringIO.new('SYNTHETIC corrupted byte source'))
    get endpoint, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('institutional_audio_integrity_failed')
    expect(response.body).not_to include(bytes, 'SYNTHETIC corrupted byte source')
  end

  it 'does not return bytes or record a successful read when a previously inspected owned file is missing' do
    expect(proof.ready?).to be(true)
    JrcContactCenter::SyntheticAudioStorageGuard.call
    version.blob.service.delete(version.blob.key)
    get endpoint, headers: headers
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body.fetch('error')).to eq('institutional_audio_bytes_unavailable')
    expect(response.body).not_to include(bytes)
    expect(Audited.audit_class.where(auditable: version, action: 'read')).to be_empty
  end

  it 'records the authorized byte read in native scoped audit without mutating the immutable version or logging private content' do
    expect(proof.ready?).to be(true)
    original = version.attributes
    get endpoint, headers: headers
    expect(response).to have_http_status(:ok)
    record = Audited.audit_class.where(auditable: version, associated: account, action: 'read').sole
    expect(record.user_id).to eq(actor.id)
    expect(record.audited_changes).to include(
      'cc_scope' => hash_including('after' => hash_including('unit_id' => unit.id.to_s)),
      'audio_read' => { 'audio_version_id' => version.id.to_s, 'inspection_id' => proof.id.to_s, 'sha256' => version.sha256 }
    )
    expect(record.audited_changes.to_json).not_to include(version.file_name, version.blob.key, version.idempotency_key, bytes)
    query = { resource_type: 'audio_version', resource_id: version.id, history: 'true', operation: 'read' }
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/configuration_audits", headers: headers, params: query
    expect(response.parsed_body.fetch('items')).to include(hash_including('operation' => 'read', 'resource_id' => version.id))
    expect(version.reload.attributes).to eq(original)
  end
end
