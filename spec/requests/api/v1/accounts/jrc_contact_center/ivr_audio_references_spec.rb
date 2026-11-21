require 'rails_helper'

RSpec.describe 'Authenticated exact institutional audio and local IVR references', type: :request do
  include_context 'with a local IVR audio reference'

  def draft_url
    "/api/v1/accounts/#{account.id}/jrc_contact_center/ivr_drafts"
  end

  def version_url(version = audio_version, asset_id: version.audio_asset_id)
    "/api/v1/accounts/#{account.id}/jrc_contact_center/audio_assets/#{asset_id}/versions/#{version.id}"
  end

  def post_draft
    post draft_url, headers: actor.create_new_auth_token, as: :json,
                    params: { ivr_draft: { name: 'SYNTHETIC exact audio draft', unit_id: unit.id, status: 'draft',
                                           expected_revision: 0, request_id: SecureRandom.uuid, definition: ivr_definition } }
  end

  it 'reads the authorized exact version metadata without exposing bytes, storage paths or signing a public URL' do
    proof = audio_proof
    get version_url, headers: actor.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to eq('no-store')
    item = response.parsed_body.fetch('item')
    expect(item).to include('id' => audio_version.id.to_s, 'sha256' => audio_version.sha256, 'ready' => false)
    expect(item.fetch('technical_verification')).to include('id' => proof.id.to_s, 'ready' => true)
    expect(response.body).not_to include('blob_id', 'signed_id', 'service_url', 'access-token', actor.email)
  end

  it 'persists, reloads and exports the authorized local graph through native APIs' do
    audio_proof
    post_draft
    expect(response).to have_http_status(:created)
    item = response.parsed_body.fetch('item')
    get "#{draft_url}/#{item.fetch('id')}", headers: actor.create_new_auth_token
    expect(response.parsed_body.fetch('item').fetch('definition')).to eq(ivr_definition)
    expect(response.parsed_body.fetch('item')).to include('local_only' => true, 'provider_applied' => false)
    get "#{draft_url}/#{item.fetch('id')}/export", params: { revision: 1 }, headers: actor.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq(ivr_definition)
  end

  it 'rejects unverified audio through the write API with no partial draft' do
    audio_version
    post_draft
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body).to include('error' => 'ivr_audio_not_verified')
    expect(JrcContactCenter::IvrDraft.where(account: account)).to be_empty
  end

  it 'does not reveal an exact version belonging to another unit even with known identifiers' do
    other = other_scope_audio(units.last)
    get version_url(other), headers: actor.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(other.sha256, other.file_name)
  end

  it 'rejects a version joined to another authorized asset instead of reading it by global ID' do
    audio_proof
    other = other_scope_audio(unit)
    get version_url(audio_version, asset_id: other.audio_asset_id), headers: actor.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(audio_version.sha256)
  end

  it 'requires configuration permission rather than recording or Nico review rights for institutional metadata' do
    audio_proof
    member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_recordings_view
                                               jrc_contact_center_recordings_listen jrc_contact_center_quality_review])
    get version_url, headers: actor.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    post_draft
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::IvrDraft.where(account: account)).to be_empty
  end

  it 'reauthorizes corporate coverage after metadata has already been read' do
    audio_proof
    get version_url, headers: actor.create_new_auth_token
    expect(response).to have_http_status(:ok)
    account.jrc_crm_user_business_units.where(user: actor).find_each { |coverage| coverage.update!(active: false) }
    get version_url, headers: actor.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    post_draft
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects cross-account metadata and graph references without changing account context' do
    foreign = create(:account)
    target = JrcContactCenter::Unit.create!(account: foreign, code: 'FOREIGN', name: 'SYNTHETIC foreign', kind: 'sac')
    version = other_scope_audio(target)
    get version_url(version), headers: actor.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    ivr_definition['nodes'][0]['audio_reference'] = audio_reference_for(version)
    post_draft
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('error' => 'ivr_unavailable_audio')
    expect(JrcContactCenter::IvrDraft.where(account: account)).to be_empty
  end
end
