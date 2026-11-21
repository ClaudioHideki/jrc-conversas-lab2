require 'rails_helper'

RSpec.describe 'Native institutional audio inspection filters preserve source version and unit authority', type: :request do
  include_context 'with an institutional audio receipt'

  let(:headers) { actor.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center/audio_assets" }
  let(:access) { JrcContactCenter::AudioLibraryAccess.new(context: context) }
  let(:receipts) do
    service = JrcContactCenter::SyntheticLegacyAudioReceipt.new(access: access)
    %w[A B C].map.with_index do |name, index|
      service.create!(unit_id: unit.id, attributes: { name: "SYNTHETIC #{name} uninspected" }, file: upload,
                      key: "synthetic-inspection-filter-#{index}")
    end
  end

  it 'distinguishes native metadata without a file from an existing file with no inspection' do
    versions = receipts
    metadata = JrcContactCenter::AudioAsset.create!(account: account, unit: unit, name: 'SYNTHETIC no file')
    get base, headers: headers, params: { unit_id: unit.id, inspection_state: 'no_file' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([metadata.id.to_s])
    expect(response.parsed_body.fetch('items').first.fetch('latest_version')).to be_nil
    get base, headers: headers, params: { unit_id: unit.id, inspection_state: 'uninspected' }
    expect(response.parsed_body.fetch('items').pluck('id')).to eq(versions.map { |row| row.audio_asset_id.to_s })
    expect(response.parsed_body.fetch('meta')).to include('total' => 3)
  end

  it 'filters an actual unavailable native scanner observation without treating it as clearance' do
    version = receipts.first
    with_modified_env JRC_CC_AUDIO_CLAMAV_SOCKET: nil do
      JrcContactCenter::AudioInspections.new(access: access).create!(
        asset_id: version.audio_asset_id, version_id: version.id, key: 'synthetic-filter-inspection-0001'
      )
    end
    get base, headers: headers, params: { unit_id: unit.id, inspection_state: 'unavailable' }
    expect(response).to have_http_status(:ok)
    item = response.parsed_body.fetch('items').sole
    expect(item.fetch('id')).to eq(version.audio_asset_id.to_s)
    expect(item.fetch('latest_version').fetch('technical_verification')).to include('state' => 'unavailable', 'ready' => false)
    get "#{base}/#{version.audio_asset_id}/versions/#{version.id}/bytes", headers: headers
    expect(response).to have_http_status(:conflict)
  end

  it 'uses the latest attempt rather than a historical clean scanner observation' do
    version = receipts.first
    service = JrcContactCenter::AudioInspections.new(access: access)
    first = service.create!(asset_id: version.audio_asset_id, version_id: version.id, key: 'synthetic-filter-inspection-clean')
    expect(first.ready?).to be(true)
    with_modified_env JRC_CC_AUDIO_CLAMAV_SOCKET: nil do
      service.create!(asset_id: version.audio_asset_id, version_id: version.id, key: 'synthetic-filter-inspection-later')
    end
    get base, headers: headers, params: { unit_id: unit.id, inspection_state: 'clean' }
    expect(response.parsed_body.fetch('items')).to be_empty
    get base, headers: headers, params: { unit_id: unit.id, inspection_state: 'unavailable' }
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([version.audio_asset_id.to_s])
    expect(version.inspections.count).to eq(2)
  end

  it 'uses a fresh clean observation instead of retaining a historical unavailable scanner state' do
    version = receipts.first
    service = JrcContactCenter::AudioInspections.new(access: access)
    with_modified_env JRC_CC_AUDIO_CLAMAV_SOCKET: nil do
      service.create!(asset_id: version.audio_asset_id, version_id: version.id, key: 'synthetic-filter-unavailable-first')
    end
    current = service.create!(asset_id: version.audio_asset_id, version_id: version.id, key: 'synthetic-filter-clean-latest')
    expect(current.ready?).to be(true)
    get base, headers: headers, params: { unit_id: unit.id, inspection_state: 'unavailable' }
    expect(response.parsed_body.fetch('items')).to be_empty
    get base, headers: headers, params: { unit_id: unit.id, inspection_state: 'clean' }
    item = response.parsed_body.fetch('items').sole
    expect(item.fetch('latest_version').fetch('technical_verification')).to include('id' => current.id.to_s, 'ready' => true)
  end

  it 'does not use an inspection of a superseded version as the result for the current version' do
    version = receipts.first
    with_modified_env JRC_CC_AUDIO_CLAMAV_SOCKET: nil do
      JrcContactCenter::AudioInspections.new(access: access).create!(
        asset_id: version.audio_asset_id, version_id: version.id, key: 'synthetic-filter-historical-proof'
      )
    end
    current = JrcContactCenter::AudioUploads.new(access: access).replace!(
      asset_id: version.audio_asset_id, file: upload, key: 'synthetic-filter-current-version',
      expected: JrcContactCenter::AudioAssetRevision.token(version.audio_asset, version: version)
    )
    get base, headers: headers, params: { unit_id: unit.id, inspection_state: 'unavailable' }
    expect(response.parsed_body.fetch('items')).to be_empty
    get base, headers: headers, params: { unit_id: unit.id, inspection_state: 'clean' }
    expect(response.parsed_body.fetch('items').sole.fetch('latest_version').fetch('id')).to eq(current.id.to_s)
    expect(version.reload.blob.download).to eq(bytes)
  end

  it 'combines the inspection filter with real origin, format and name before native pagination totals' do
    versions = receipts
    values = { unit_id: unit.id, inspection_state: 'uninspected', source_kind: 'user_upload', content_type: 'audio/wav',
               q: 'SYNTHETIC', per_page: 1 }
    get base, headers: headers, params: values.merge(page: 1)
    expect(response.parsed_body.fetch('meta')).to include('total' => 3, 'pages' => 3, 'page' => 1)
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([versions.first.audio_asset_id.to_s])
    get base, headers: headers, params: values.merge(page: 2)
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([versions.second.audio_asset_id.to_s])
    get base, headers: headers, params: { unit_id: unit.id, inspection_state: '' }
    expect(response.parsed_body.fetch('meta')).to include('total' => 3)
  end

  ['ready', false, ['clean'], { state: 'clean' }].each do |invalid|
    it "rejects unsupported or malformed inspection filter #{invalid.inspect} without returning a broader list" do
      get base, headers: headers, params: { unit_id: unit.id, inspection_state: invalid }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.fetch('error')).to eq('invalid_institutional_audio_filter')
      expect(response.parsed_body).not_to have_key('items')
    end
  end

  it 'does not let a requested inspection state grant another unit, account or recording-only profile access' do
    get base, headers: headers, params: { unit_id: units.last.id, inspection_state: 'no_file' }
    expect(response).to have_http_status(:not_found)
    other = create(:account)
    foreign_base = base.sub("/accounts/#{account.id}/", "/accounts/#{other.id}/")
    get foreign_base, headers: headers, params: { unit_id: unit.id, inspection_state: 'uninspected' }
    expect(response).to have_http_status(:unauthorized)
    member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_recordings_listen])
    get base, headers: headers, params: { unit_id: unit.id, inspection_state: 'no_file' }
    expect(response).to have_http_status(:unauthorized)
  end
end
