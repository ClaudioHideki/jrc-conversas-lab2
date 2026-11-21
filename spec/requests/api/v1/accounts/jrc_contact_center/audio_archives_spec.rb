require 'rails_helper'
require 'zip'
require 'stringio'

RSpec.describe 'Private selected institutional audio downloads retain native authority', type: :request do
  include_context 'with an institutional audio receipt'

  let(:headers) { actor.create_new_auth_token }
  let(:version) do
    access = JrcContactCenter::AudioLibraryAccess.new(context: context)
    JrcContactCenter::AudioUploads.new(access: access).create!(
      unit_id: unit.id, attributes: { name: 'SYNTHETIC selected archive' }, file: upload, key: key
    )
  end
  let(:items) do
    [{ audio_asset_id: version.audio_asset_id.to_s, audio_version_id: version.id.to_s,
       inspection_id: version.reload.latest_inspection.id.to_s, sha256: version.sha256 }]
  end
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/audio_archives" }

  it 'returns exact verified bytes and a private manifest with independently verifiable identity headers' do
    post endpoint, headers: headers, params: { items: items }, as: :json
    expect(response).to have_http_status(:ok)
    expect([response.media_type, response.headers['Cache-Control'], response.headers['X-Content-Type-Options']])
      .to eq(['application/zip', 'no-store', 'nosniff'])
    expected = [account.id.to_s, unit.id.to_s, '1', Digest::SHA256.hexdigest(response.body.b), response.body.bytesize.to_s]
    expect(response.headers.values_at('X-JRC-Audio-Account', 'X-JRC-Audio-Unit', 'X-JRC-Audio-Count', 'X-JRC-Audio-SHA256', 'X-JRC-Audio-Bytes'))
      .to eq(expected)
    Zip::File.open_buffer(StringIO.new(response.body.b)) do |archive|
      entry = JSON.parse(archive.read('manifesto.json')).fetch('items').sole
      expect(archive.read(entry.fetch('archive_name'))).to eq(bytes)
      expect(entry).to include('audio_asset_id' => version.audio_asset_id.to_s, 'audio_version_id' => version.id.to_s)
    end
    expect(Audited.audit_class.where(auditable: version, action: 'read').count).to eq(1)
  end

  it 'rejects root grants, storage locators and missing items without releasing private bytes' do
    %w[account_id user_id unit_id blob_id signed_id].each do |name|
      post endpoint, headers: headers, params: { items: items, name => '999' }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    post endpoint, headers: headers, params: {}, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).not_to include(bytes)
  end

  it 'refuses missing authentication and foreign-account credentials on a genuine selection' do
    foreign = create(:user, account: create(:account))
    post endpoint, params: { items: items }, as: :json
    expect(response).to have_http_status(:unauthorized)
    post endpoint, headers: foreign.create_new_auth_token, params: { items: items }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(bytes)
  end

  it 'refuses a real source outside the current native unit coverage' do
    selection = items
    hidden = JrcContactCenter::AudioAsset.create!(account: account, unit: units.last, name: 'SYNTHETIC hidden archive')
    selection.first[:audio_asset_id] = hidden.id.to_s
    post endpoint, headers: headers, params: { items: selection }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(bytes, hidden.name)
    expect(Audited.audit_class.where(auditable: version, action: 'read')).to be_empty
  end

  it 'does not treat recording-listen or Nico review permission as institutional configuration authority' do
    selection = items
    member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_recordings_listen jrc_contact_center_quality_review])
    post endpoint, headers: headers, params: { items: selection }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(bytes)
    expect(response.headers['Cache-Control']).to eq('no-store')
  end

  it 'rejects a superseded proof with a genuine current source instead of downloading a different revision' do
    selection = items
    access = JrcContactCenter::AudioLibraryAccess.new(context: context)
    JrcContactCenter::AudioInspections.new(access: access).create!(
      asset_id: version.audio_asset_id, version_id: version.id, key: 'synthetic-archive-api-proof-002'
    )
    post endpoint, headers: headers, params: { items: selection }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('institutional_audio_archive_source_changed')
    expect(response.body).not_to include(bytes)
  end

  it 'keeps a corrupted source from producing a successful or partial ZIP response' do
    selection = items
    version.blob.service.upload(version.blob.key, StringIO.new('SYNTHETIC changed archive bytes'))
    post endpoint, headers: headers, params: { items: selection }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('institutional_audio_integrity_failed')
    expect(response.media_type).to eq('application/json')
    expect(response.body).not_to include(bytes, 'SYNTHETIC changed archive bytes')
  end
end
