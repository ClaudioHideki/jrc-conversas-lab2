require 'rails_helper'

RSpec.describe 'Selected institutional audio moves retain native account/unit authority and CAS', type: :request do
  include_context 'with an institutional audio receipt'

  let(:headers) { actor.create_new_auth_token }
  let(:assets) do
    Array.new(2) { |index| JrcContactCenter::AudioAsset.create!(account: account, unit: unit, name: "SYNTHETIC HTTP move #{index}") }
  end
  let(:folder) { JrcContactCenter::AudioFolder.create!(account: account, unit: unit, name: 'SYNTHETIC HTTP destination') }
  let(:body) do
    { unit_id: unit.id.to_s, folder_id: folder.id.to_s, items: assets.map do |record|
      { audio_asset_id: record.id.to_s, expected_revision: JrcContactCenter::AudioAssetRevision.token(record, version: nil) }
    end }
  end

  def endpoint
    "/api/v1/accounts/#{account.id}/jrc_contact_center/audio_asset_moves"
  end

  it 'persists a same-unit selection and returns current native metadata without storage capabilities' do
    post endpoint, headers: headers, params: body, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('account_id')).to eq(account.id.to_s)
    expect(response.parsed_body.fetch('items').pluck('folder_id')).to eq([folder.id.to_s, folder.id.to_s])
    expect(assets.map { |record| record.reload.folder_id }).to eq([folder.id, folder.id])
    expect(response.headers['Cache-Control']).to eq('no-store')
    expect(response.body).not_to match(/blob_id|signed_id|service_url|idempotency_key/)
  end

  it 'does not silently replay a stale response as a new metadata write' do
    payload = body
    post endpoint, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:ok)
    count = Audited.audit_class.where(auditable: assets).count
    post endpoint, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('stale_configuration_revision')
    expect(Audited.audit_class.where(auditable: assets).count).to eq(count)
  end

  it 'requires the explicit destination key and rejects extra actor/account authority fields' do
    payload = body
    [payload.except(:folder_id), payload.merge(account_id: 999), payload.merge(user_id: 999)].each do |invalid|
      post endpoint, headers: headers, params: invalid, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(assets.map { |record| record.reload.folder_id }).to eq([nil, nil])
  end

  it 'rejects a source in a denied unit instead of partially moving the other records' do
    payload = body
    hidden = JrcContactCenter::AudioAsset.create!(account: account, unit: units.last, name: 'SYNTHETIC denied HTTP source')
    payload[:items] << { audio_asset_id: hidden.id.to_s, expected_revision: JrcContactCenter::AudioAssetRevision.token(hidden, version: nil) }
    post endpoint, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(hidden.name)
    expect(assets.map { |record| record.reload.folder_id }).to eq([nil, nil])
    expect(hidden.reload.folder_id).to be_nil
  end

  it 'denies another account session and preserves all selected metadata' do
    payload = body
    foreign = create(:user, account: create(:account))
    post endpoint, headers: foreign.create_new_auth_token, params: payload, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(assets.map { |record| record.reload.folder_id }).to eq([nil, nil])
  end

  it 'denies the current profile after withdrawal despite a valid revision and account session' do
    payload = body
    member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_recordings_listen])
    post endpoint, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(assets.map { |record| record.reload.folder_id }).to eq([nil, nil])
  end

  it 'allows explicit root reorganization without deleting or replacing the selected identities' do
    assets.each { |record| record.update!(folder: folder) }
    payload = body.merge(folder_id: nil)
    post endpoint, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').pluck('id')).to eq(assets.map { |record| record.id.to_s })
    expect(assets.map { |record| record.reload.folder_id }).to eq([nil, nil])
    expect(JrcContactCenter::AudioVersion.where(account: account)).to be_empty
  end
end
