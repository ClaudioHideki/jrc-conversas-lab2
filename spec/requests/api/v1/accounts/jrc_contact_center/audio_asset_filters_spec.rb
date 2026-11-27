require 'rails_helper'

RSpec.describe 'Native scoped institutional audio filters use only the latest version', type: :request do
  include_context 'with an institutional audio receipt'

  let(:headers) { actor.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center/audio_assets" }
  let(:access) { JrcContactCenter::AudioLibraryAccess.new(context: context) }
  let(:receipts) do
    service = JrcContactCenter::AudioUploads.new(access: access)
    first = service.create!(unit_id: unit.id, attributes: { name: 'SYNTHETIC A replaced' }, file: upload, key: 'synthetic-filter-receipt-001')
    second = service.create!(unit_id: unit.id, attributes: { name: 'SYNTHETIC B capture' }, file: upload,
                             key: 'synthetic-filter-receipt-002', source_kind: 'browser_capture')
    third = service.create!(unit_id: unit.id, attributes: { name: 'SYNTHETIC C upload' }, file: upload, key: 'synthetic-filter-receipt-003')
    replacement = service.replace!(asset_id: first.audio_asset_id, file: upload, key: 'synthetic-filter-receipt-004', source_kind: 'browser_capture',
                                   expected: JrcContactCenter::AudioAssetRevision.token(first.audio_asset, version: first))
    { replaced: replacement, captured: second, uploaded: third, old: first }
  end

  it 'excludes a historical upload origin when the current exact version is captured' do
    data = receipts
    get base, headers: headers, params: { unit_id: unit.id, source_kind: 'user_upload' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([data.fetch(:uploaded).audio_asset_id.to_s])
    expect(response.parsed_body.fetch('meta')).to include('total' => 1, 'pages' => 1)
  end

  it 'combines current origin, real format and name before native totals and bounded pagination' do
    data = receipts
    values = { unit_id: unit.id, source_kind: 'browser_capture', content_type: 'audio/wav', q: 'SYNTHETIC', per_page: 1 }
    get base, headers: headers, params: values.merge(page: 1)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('meta')).to include('page' => 1, 'pages' => 2, 'per_page' => 1, 'total' => 2)
    expect(response.parsed_body.fetch('items').first).to include('id' => data.fetch(:replaced).audio_asset_id.to_s)
    expect(response.parsed_body.fetch('items').first.fetch('latest_version')).to include('number' => 2, 'source_kind' => 'browser_capture')
    get base, headers: headers, params: values.merge(page: 2)
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([data.fetch(:captured).audio_asset_id.to_s])
  end

  it 'uses actual canonical MIME and preserves an unfiltered list instead of duplicating version rows' do
    receipts
    get base, headers: headers, params: { unit_id: unit.id, content_type: 'audio/mpeg' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to be_empty
    get base, headers: headers, params: { unit_id: unit.id, content_type: 'audio/wav' }
    expect(response.parsed_body.fetch('meta')).to include('total' => 3)
    get base, headers: headers, params: { unit_id: unit.id }
    expect(response.parsed_body.fetch('meta')).to include('total' => 3)
  end

  [
    { source_kind: 'nico' }, { source_kind: false }, { source_kind: ['user_upload'] },
    { source_kind: { name: 'browser_capture' } }, { content_type: 'audio/x-wav' }, { content_type: ['audio/wav'] }
  ].each do |filters|
    it "rejects malformed or unsupported filters #{filters.inspect} without returning an unfiltered fallback" do
      get base, headers: headers, params: { unit_id: unit.id }.merge(filters)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.fetch('error')).to eq('invalid_institutional_audio_filter')
      expect(response.parsed_body).not_to have_key('items')
    end
  end

  it 'never grants unit coverage or configuration through filter values or recording-only roles' do
    get base, headers: headers, params: { unit_id: units.last.id, source_kind: 'browser_capture' }
    expect(response).to have_http_status(:not_found)
    member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_recordings_listen])
    get base, headers: headers, params: { unit_id: unit.id, content_type: 'audio/wav' }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'combines actual institutional usage with name and latest version filters before totals and pagination' do
    data = receipts
    [data.fetch(:replaced), data.fetch(:captured)].each { |version| version.audio_asset.update!(purpose: 'SYNTHETIC URA welcome') }
    data.fetch(:uploaded).audio_asset.update!(purpose: 'SYNTHETIC hold music')
    values = { unit_id: unit.id, q: 'SYNTHETIC', source_kind: 'browser_capture', content_type: 'audio/wav', purpose: ' ura ', per_page: 1 }
    get base, headers: headers, params: values.merge(page: 1)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('meta')).to include('total' => 2, 'pages' => 2, 'page' => 1)
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([data.fetch(:replaced).audio_asset_id.to_s])
    get base, headers: headers, params: values.merge(page: 2)
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([data.fetch(:captured).audio_asset_id.to_s])
  end

  it 'searches percent underscores and SQL-looking usage text literally without widening the authorized set' do
    data = receipts
    data.fetch(:uploaded).audio_asset.update!(purpose: "SYNTHETIC 10%_welcome' OR 1=1")
    data.fetch(:captured).audio_asset.update!(purpose: 'SYNTHETIC 10AAwelcome')
    get base, headers: headers, params: { unit_id: unit.id, purpose: "%_welcome' OR 1=1" }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([data.fetch(:uploaded).audio_asset_id.to_s])
    expect(response.parsed_body.fetch('meta').fetch('total')).to eq(1)
  end

  it 'does not grant another unit or audio configuration through a usage filter' do
    get base, headers: headers, params: { unit_id: units.last.id, purpose: 'URA' }
    expect(response).to have_http_status(:not_found)
    member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_recordings_listen])
    get base, headers: headers, params: { unit_id: unit.id, purpose: 'URA' }
    expect(response).to have_http_status(:unauthorized)
  end

  [{ purpose: ['ivr'] }, { purpose: { name: 'ivr' } }, { purpose: 'x' * 161 }].each do |filters|
    it "rejects malformed institutional usage search #{filters.inspect} without unfiltered fallback" do
      get base, headers: headers, params: { unit_id: unit.id }.merge(filters)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.fetch('error')).to eq('invalid_institutional_audio_filter')
      expect(response.parsed_body).not_to have_key('items')
    end
  end
end
