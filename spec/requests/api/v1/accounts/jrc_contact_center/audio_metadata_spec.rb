require 'rails_helper'

# Positive metadata comes from the owned native scanner/decoder and exact persisted observations.
RSpec.describe 'Institutional audio list metadata remains current and scoped', type: :request do
  include_context 'with an institutional audio receipt'

  let(:headers) { actor.create_new_auth_token }
  let(:access) { JrcContactCenter::AudioLibraryAccess.new(context: context) }
  let(:version) do
    JrcContactCenter::AudioUploads.new(access: access)
                                  .create!(unit_id: unit.id, attributes: { name: 'SYNTHETIC current metadata' }, file: upload, key: key)
  end
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center/audio_assets" }

  it 'returns only actual duration and format for the exact current observation without granting publication' do
    source = version
    get base, headers: headers, params: { unit_id: unit.id, per_page: 1 }
    expect(response).to have_http_status(:ok)
    returned = response.parsed_body.fetch('items').sole.fetch('latest_version')
    proof = returned.fetch('technical_verification')
    expect(proof).to include('audio_version_id' => source.id.to_s, 'ready' => true, 'state' => 'clean', 'probe_state' => 'valid')
    expect(proof.fetch('metadata')).to include('duration_ms' => 1, 'codec' => 'pcm_s16le', 'sample_rate' => 8_000)
    expect(returned.fetch('ready')).to be(false)
    expect(proof.keys).not_to include('source_blob_id', 'idempotency_key', 'input_digest', 'signed_id', 'key')
  end

  it 'does not invent zero duration or a clean status for historical quarantine without any observation' do
    legacy = JrcContactCenter::SyntheticLegacyAudioReceipt.new(access: access)
    source = legacy.create!(unit_id: unit.id, attributes: { name: 'SYNTHETIC unverified metadata' }, file: upload, key: key)
    get "#{base}/#{source.audio_asset_id}", headers: headers
    expect(response).to have_http_status(:ok)
    returned = response.parsed_body.fetch('item').fetch('latest_version')
    expect(returned.fetch('technical_verification')).to be_nil
    expect(returned.fetch('ready')).to be(false)
    expect(source.inspections).to be_empty
  end

  it 'hides earlier clean metadata when the latest actual inspection is unavailable' do
    source = version
    first = source.inspections.sole
    with_modified_env JRC_CC_AUDIO_CLAMAV_SOCKET: nil do
      JrcContactCenter::AudioInspections.new(access: access).create!(
        asset_id: source.audio_asset_id, version_id: source.id, key: 'synthetic-metadata-inspection-002'
      )
    end
    get "#{base}/#{source.audio_asset_id}", headers: headers
    proof = response.parsed_body.fetch('item').fetch('latest_version').fetch('technical_verification')
    expect(proof).to include('state' => 'unavailable', 'ready' => false, 'metadata' => {})
    expect(proof.fetch('id')).not_to eq(first.id.to_s)
    expect(first.reload.ready?).to be(true)
    expect(source.inspections.count).to eq(2)
  end

  it 'does not let recording-listen permission substitute for the current library configuration authority' do
    source = version
    member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_recordings_listen])
    get "#{base}/#{source.audio_asset_id}", headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(source.sha256, 'pcm_s16le', 'technical_verification')
  end

  it 'does not publish technical metadata when a foreign account supplies genuine own unit and asset identifiers' do
    source = version
    foreign = create(:user, account: create(:account))
    get base, headers: foreign.create_new_auth_token, params: { unit_id: unit.id }
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(source.sha256, 'pcm_s16le', 'technical_verification')
  end
end
