require 'rails_helper'

RSpec.describe 'Authorized institutional audio local IVR usages', type: :request do
  include_context 'with a local IVR audio reference'

  before { audio_proof }

  def usage_url(asset_id = audio_version.audio_asset_id)
    "/api/v1/accounts/#{account.id}/jrc_contact_center/audio_assets/#{asset_id}/usages"
  end

  def write_graph(graph = ivr_definition, previous: nil, name: 'SYNTHETIC referenced draft', status: 'draft')
    input = JrcContactCenter::IvrDraftInput.new(
      name: name, status: status, definition: graph,
      expected_revision: previous ? previous.fetch(:version).revision : 0, request_id: SecureRandom.uuid
    )
    JrcContactCenter::IvrDraftWrite.new(context: context).call(input: input, unit_id: unit.id, id: previous&.fetch(:draft)&.id)
  end

  it 'returns exact authorized local references without audio, full graphs or provider confirmation' do
    result = write_graph
    get usage_url, headers: actor.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to eq('no-store')
    expect(response.parsed_body).to include('coverage' => 'current_local_ivr_drafts_only', 'provider_configuration_verified' => false)
    item = response.parsed_body.fetch('items').sole
    expect(item).to include('draft_id' => result.fetch(:draft).id.to_s, 'draft_revision' => 1, 'local_only' => true, 'provider_applied' => false)
    expect(item.fetch('references').sole).to eq('node_id' => 'entry', 'audio_version_id' => audio_version.id.to_s, 'sha256' => audio_version.sha256)
    expect(response.body).not_to include('definition', 'blob_id', 'service_url', 'access-token', actor.email)
  end

  it 'returns no current usage after unlinking while retaining the original immutable version' do
    result = write_graph
    unlinked = ivr_definition.deep_dup
    unlinked.fetch('nodes').first.delete('audio_reference')
    write_graph(unlinked, previous: result)
    get usage_url, headers: actor.create_new_auth_token
    expect(response.parsed_body.fetch('items')).to be_empty
    expect(response.parsed_body.fetch('meta').fetch('total')).to eq(0)
    expect(result.fetch(:draft).versions.find_by!(revision: 1).definition).to eq(ivr_definition)
  end

  it 'distinguishes an archived local head without claiming the provider has removed the reference' do
    result = write_graph
    write_graph(previous: result, status: 'archived')
    get usage_url, headers: actor.create_new_auth_token
    expect(response.parsed_body.fetch('items').sole).to include('status' => 'archived', 'draft_revision' => 2, 'provider_applied' => false)
    expect(result.fetch(:draft).versions.count).to eq(2)
  end

  it 'counts drafts rather than menu occurrences and preserves each exact menu reference' do
    graph = ivr_definition.deep_dup
    second = graph.fetch('nodes').first.deep_dup.merge('id' => 'second')
    graph.fetch('nodes').first.fetch('options') << { 'digit' => '2', 'target' => 'second' }
    graph.fetch('nodes') << second
    write_graph(graph)
    get usage_url, headers: actor.create_new_auth_token
    expect(response.parsed_body.fetch('meta').fetch('total')).to eq(1)
    expect(response.parsed_body.fetch('items').sole.fetch('references').pluck('node_id')).to contain_exactly('entry', 'second')
  end

  it 'keeps the pinned version when a newer institutional file is received' do
    write_graph
    asset = library.asset(audio_version.audio_asset_id)
    revision = JrcContactCenter::AudioAssetRevision.token(asset, version: library.latest(asset))
    second = JrcContactCenter::AudioUploads.new(access: library).replace!(
      asset_id: audio_version.audio_asset_id, file: upload, key: 'synthetic-usage-later-audio',
      expected: revision
    )
    get usage_url, headers: actor.create_new_auth_token
    expect(response.parsed_body.fetch('items').sole.fetch('references').sole.fetch('audio_version_id')).to eq(audio_version.id.to_s)
    expect(second.id).not_to eq(audio_version.id)
  end

  it 'paginates distinct current draft heads in stable order and does not repeat a draft' do
    3.times { |index| write_graph(name: "SYNTHETIC draft #{index}") }
    get usage_url, params: { page: 1, per_page: 1 }, headers: actor.create_new_auth_token
    first = response.parsed_body
    get usage_url, params: { page: 2, per_page: 1 }, headers: actor.create_new_auth_token
    second = response.parsed_body
    expect(first.fetch('meta')).to include('page' => 1, 'per_page' => 1, 'total' => 3, 'pages' => 3)
    expect(second.fetch('meta')).to include('page' => 2, 'total' => 3)
    expect(first.fetch('items').sole.fetch('draft_id')).not_to eq(second.fetch('items').sole.fetch('draft_id'))
  end

  it 'bounds the result limit even when no page or an excessive limit is provided' do
    write_graph
    get usage_url, params: { per_page: 10_000 }, headers: actor.create_new_auth_token
    expect(response.parsed_body.fetch('meta')).to include('page' => 1, 'per_page' => 20, 'total' => 1)
  end

  it 'does not expose another unit through a known asset identity' do
    other = other_scope_audio(units.last)
    get usage_url(other.audio_asset_id), headers: actor.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(other.sha256, 'SYNTHETIC separately authorized audio')
  end

  it 'does not expose another account through a known asset identity' do
    foreign = create(:account)
    other_unit = JrcContactCenter::Unit.create!(account: foreign, code: 'OTHER', name: 'SYNTHETIC other', kind: 'sac')
    other = other_scope_audio(other_unit)
    get usage_url(other.audio_asset_id), headers: actor.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(other.sha256, 'SYNTHETIC separately authorized audio')
  end

  it 'retains the native historical scope restriction after a unit is remapped' do
    write_graph
    unit.update!(settings: units.last.settings.deep_dup)
    account.jrc_crm_user_business_units.find_by!(user: actor).update!(business_unit_id: units.last.settings.fetch('business_unit_id'))
    get usage_url, headers: actor.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to be_empty
    expect(response.body).not_to include('SYNTHETIC referenced draft')
  end

  it 'reauthorizes corporate coverage on a subsequent request' do
    write_graph
    get usage_url, headers: actor.create_new_auth_token
    expect(response.parsed_body.fetch('items').length).to eq(1)
    account.jrc_crm_user_business_units.find_by!(user: actor).update!(active: false)
    get usage_url, headers: actor.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('SYNTHETIC referenced draft')
  end

  it 'does not substitute recording or Nico review permissions for institutional configuration' do
    write_graph
    member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_recordings_view
                                               jrc_contact_center_recordings_listen jrc_contact_center_quality_review])
    get usage_url, headers: actor.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('SYNTHETIC referenced draft')
  end

  it 'is read only and does not create versions, inspections or configuration audits' do
    write_graph
    headers = actor.create_new_auth_token
    before = [JrcContactCenter::IvrDraftVersion.count, JrcContactCenter::AudioVersion.count,
              JrcContactCenter::AudioInspection.count, Audited.audit_class.count]
    get usage_url, headers: headers
    expect(response).to have_http_status(:ok)
    expect([JrcContactCenter::IvrDraftVersion.count, JrcContactCenter::AudioVersion.count,
            JrcContactCenter::AudioInspection.count, Audited.audit_class.count]).to eq(before)
  end
end
