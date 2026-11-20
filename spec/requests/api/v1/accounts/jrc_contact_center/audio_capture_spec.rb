require 'rails_helper'

# Native stored bytes, scanner and decoder; source_kind is declared provenance, never a capability.
RSpec.describe 'Institutional browser capture reuses private native admission', type: :request do
  include_context 'with an institutional audio receipt'

  let(:headers) { actor.create_new_auth_token }
  let(:multipart_file) { Rack::Test::UploadedFile.new(StringIO.new(bytes), 'audio/wav', original_filename: 'SYNTHETIC.wav') }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center/audio_assets" }

  after { multipart_file.close }

  it 'accepts declared capture origin only through actual scanner and codec admission with immutable evidence' do
    post base, headers: headers,
               params: { asset: { name: 'SYNTHETIC capture' }, unit_id: unit.id, file: multipart_file,
                         idempotency_key: key, source_kind: 'browser_capture' }
    expect(response).to have_http_status(:created)
    version = JrcContactCenter::AudioVersion.find(response.parsed_body.fetch('received_version').fetch('id'))
    expect(version).to have_attributes(source_kind: 'browser_capture', sha256: Digest::SHA256.hexdigest(bytes), unit_id: unit.id)
    expect(version.inspections.sole.ready?).to be(true)
    expect(version.blob.download).to eq(bytes)
    expect(response.parsed_body.fetch('received_version')).to include('source_kind' => 'browser_capture', 'ready' => false)
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  [nil, false, 'nico', 'provider_published', ['browser_capture'], { 'kind' => 'browser_capture' }].each do |source|
    it "rejects invalid capture origin #{source.inspect} before staging or final persistence" do
      original = ActiveStorage::Blob.count
      post base, headers: headers,
                 params: { asset: { name: 'SYNTHETIC invalid origin' }, unit_id: unit.id, file: multipart_file,
                           idempotency_key: key, source_kind: source }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.fetch('error')).to eq('invalid_institutional_audio_source')
      expect(JrcContactCenter::AudioAsset.where(account: account)).to be_empty
      expect(JrcContactCenter::AudioVersion.where(account: account)).to be_empty
      expect(ActiveStorage::Blob.count).to eq(original)
    end
  end

  it 'preserves the canonical historical upload digest and never silently reclassifies an accepted old receipt' do
    access = JrcContactCenter::AudioLibraryAccess.new(context: context)
    old = JrcContactCenter::SyntheticLegacyAudioReceipt.new(access: access)
                                                       .create!(unit_id: unit.id, attributes: { name: 'SYNTHETIC legacy' }, file: upload, key: key)
    with_modified_env JRC_CC_AUDIO_CLAMAV_SOCKET: nil do
      post base, headers: headers,
                 params: { asset: { name: 'SYNTHETIC legacy' }, unit_id: unit.id, file: multipart_file, idempotency_key: key }
    end
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.fetch('received_version')).to include('id' => old.id.to_s, 'source_kind' => 'user_upload')
    expect(old.reload.inspections).to be_empty
    expect(JrcContactCenter::AudioVersion.where(account: account).count).to eq(1)
  end

  it 'returns an exact capture replay but rejects a changed source for the same idempotency key' do
    params = { asset: { name: 'SYNTHETIC capture replay' }, unit_id: unit.id, file: multipart_file,
               idempotency_key: key, source_kind: 'browser_capture' }
    post base, headers: headers, params: params
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch('received_version').fetch('id')
    with_modified_env JRC_CC_AUDIO_CLAMAV_SOCKET: nil do
      post base, headers: headers, params: params
      expect(response.parsed_body.fetch('received_version').fetch('id')).to eq(id)
    end
    post base, headers: headers, params: params.merge(source_kind: 'user_upload')
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('institutional_audio_upload_key_conflict')
    expect(JrcContactCenter::AudioVersion.where(account: account).count).to eq(1)
    expect(JrcContactCenter::AudioVersion.find(id).inspections.count).to eq(1)
  end

  it 'never uses capture origin to obtain another unit or recording-only permission' do
    values = { asset: { name: 'SYNTHETIC denied capture' }, unit_id: units.last.id, file: multipart_file,
               idempotency_key: key, source_kind: 'browser_capture' }
    post base, headers: headers, params: values
    expect(response).to have_http_status(:not_found)
    member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_recordings_listen])
    post base, headers: headers, params: values.merge(unit_id: unit.id)
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::AudioVersion.where(account: account)).to be_empty
  end

  it 'pins source independently for replacement versions without rewriting the accepted upload' do
    post base, headers: headers,
               params: { asset: { name: 'SYNTHETIC replaced capture' }, unit_id: unit.id, file: multipart_file, idempotency_key: key }
    expect(response).to have_http_status(:created)
    accepted = response.parsed_body.fetch('item')
    endpoint = "#{base}/#{accepted.fetch('id')}/versions"
    post endpoint, headers: headers,
                   params: { file: multipart_file, idempotency_key: 'synthetic-capture-replacement-001', source_kind: 'browser_capture',
                             expected_revision: accepted.fetch('revision') }
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.fetch('received_version')).to include('number' => 2, 'source_kind' => 'browser_capture')
    versions = JrcContactCenter::AudioVersion.where(audio_asset_id: accepted.fetch('id')).order(:number)
    expect(versions.pluck(:source_kind)).to eq(%w[user_upload browser_capture])
    expect(versions.map { |version| version.inspections.sole.ready? }).to eq([true, true])
    expect(versions.map { |version| version.blob.download }).to eq([bytes, bytes])
  end

  it 'does not grant membership or upload access across accounts for captured input' do
    foreign = create(:account)
    foreign.enable_features!('jrc_contact_center')
    endpoint = "/api/v1/accounts/#{foreign.id}/jrc_contact_center/audio_assets"
    post endpoint, headers: headers,
                   params: { asset: { name: 'SYNTHETIC foreign capture' }, unit_id: unit.id, file: multipart_file,
                             idempotency_key: key, source_kind: 'browser_capture' }
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::AudioAsset.where(account: foreign)).to be_empty
    expect(JrcContactCenter::AudioVersion.where(account: account)).to be_empty
  end
end
