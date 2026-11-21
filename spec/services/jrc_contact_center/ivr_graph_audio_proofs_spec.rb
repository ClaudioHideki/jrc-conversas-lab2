require 'rails_helper'

RSpec.describe JrcContactCenter::IvrGraph, '#audio_proofs' do
  include_context 'with a local IVR audio reference'

  def build_graph
    described_class.new(ivr_definition, access: graph_access, unit_id: unit.id)
  end

  it 'pins an exact authorized version with a current real observation without reading audio bytes' do
    proof = audio_proof
    storage = audio_version.blob.service
    expect(proof.ready?).to be(true)
    expect(storage).not_to receive(:open)
    expect(storage).not_to receive(:download)
    graph = build_graph
    expect(graph.data).to eq(ivr_definition)
    expect(graph.audio_proofs).to eq([audio_reference_for(audio_version).merge('inspection_id' => proof.id.to_s)])
    expect(graph.data.to_json).not_to include('provider_applied', 'blob_id', 'recording_url')
  end

  it 'does not make an unverified private receipt usable as a menu announcement' do
    audio_version
    expect { build_graph }.to raise_error(JrcContactCenter::OperationError) { |error| expect(error.code).to eq('ivr_audio_not_verified') }
    expect(JrcContactCenter::AudioInspection.where(audio_version: audio_version)).to be_empty
  end

  it 'rejects a supplied hash that does not match the immutable selected version' do
    audio_proof
    ivr_definition['nodes'][0]['audio_reference']['sha256'] = '0' * 64
    expect { build_graph }.to raise_error(JrcContactCenter::OperationError, 'ivr_unavailable_audio')
  end

  it 'does not reuse a previous ready inspection after a current unavailable observation' do
    original = audio_proof
    with_modified_env JRC_CC_AUDIO_CLAMAV_SOCKET: nil do
      JrcContactCenter::AudioInspections.new(access: library).create!(
        asset_id: audio_version.audio_asset_id, version_id: audio_version.id, key: 'synthetic-ivr-audio-proof-002'
      )
    end
    expect { build_graph }.to raise_error(JrcContactCenter::OperationError, 'ivr_audio_not_verified')
    expect(original.reload.ready?).to be(true)
  end

  it 'rejects an actually inspected version in a different unit without expanding current corporate coverage' do
    audio_proof
    foreign = other_scope_audio(units.last)
    ivr_definition['nodes'][0]['audio_reference'] = audio_reference_for(foreign)
    expect(foreign.latest_inspection.ready?).to be(true)
    expect { build_graph }.to raise_error(JrcContactCenter::OperationError, 'ivr_unavailable_audio')
    expect(library.units.pluck(:id)).to eq([unit.id])
  end

  it 'rejects an inspected version in another account even when the full reference is supplied' do
    audio_proof
    foreign_account = create(:account)
    target = JrcContactCenter::Unit.create!(account: foreign_account, code: 'FOREIGN', name: 'SYNTHETIC foreign', kind: 'sac')
    foreign = other_scope_audio(target)
    ivr_definition['nodes'][0]['audio_reference'] = audio_reference_for(foreign)
    expect(foreign.latest_inspection.ready?).to be(true)
    expect { build_graph }.to raise_error(JrcContactCenter::OperationError, 'ivr_unavailable_audio')
  end

  it 'does not join a version to a different asset even inside the authorized unit' do
    audio_proof
    other = other_scope_audio(unit)
    ivr_definition['nodes'][0]['audio_reference'].merge!('version_id' => other.id.to_s, 'sha256' => other.sha256)
    expect { build_graph }.to raise_error(JrcContactCenter::OperationError, 'ivr_unavailable_audio')
  end

  it 'does not redirect a pinned version when another library version becomes the latest' do
    audio_proof
    definition = ivr_definition.deep_dup
    replacement = bytes.dup
    replacement[-16, 16] = Array.new(8, 1).pack('s<*')
    upload.tempfile.rewind
    upload.tempfile.write(replacement)
    upload.tempfile.flush
    upload.tempfile.rewind
    asset = library.asset(audio_version.audio_asset_id)
    expected = JrcContactCenter::AudioAssetRevision.token(asset)
    latest = JrcContactCenter::AudioUploads.new(access: library).replace!(
      asset_id: asset.id, file: upload, key: 'synthetic-ivr-audio-replacement', expected: expected
    )
    graph = build_graph
    expect(latest.number).to eq(2)
    expect(latest.sha256).not_to eq(audio_version.sha256)
    expect(graph.data).to eq(definition)
    expect(graph.audio_proofs.sole.fetch('version_id')).to eq(audio_version.id.to_s)
    expect(audio_version.reload.blob.download).to eq(bytes)
  end

  it 'checks current technical readiness again when an already validated graph is copied for simulation' do
    audio_proof
    graph = build_graph
    with_modified_env JRC_CC_AUDIO_CLAMAV_SOCKET: nil do
      JrcContactCenter::AudioInspections.new(access: library).create!(
        asset_id: audio_version.audio_asset_id, version_id: audio_version.id, key: 'synthetic-ivr-audio-proof-003'
      )
    end
    expect { graph.authorized_copy }.to raise_error(JrcContactCenter::OperationError, 'ivr_audio_not_verified')
    expect(graph.data).to eq(ivr_definition)
  end

  it 'does not let the separate Nico review permission grant configuration or institutional audio access' do
    audio_proof
    permissions = %w[
      jrc_contact_center_view jrc_contact_center_recordings_view
      jrc_contact_center_recordings_listen jrc_contact_center_quality_review
    ]
    member.custom_role.update!(permissions: permissions)
    expect(JrcContactCenter::ModulePolicy.new(context, :contact_center).quality_review?).to be(true)
    expect { build_graph }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rejects contradictory references to one version rather than silently retaining the first hash' do
    audio_proof
    copied = ivr_definition['nodes'][0].deep_dup
    copied['id'] = 'another_menu'
    copied['audio_reference']['sha256'] = '0' * 64
    ivr_definition['nodes'] << copied
    expect { build_graph }.to raise_error(JrcContactCenter::OperationError, 'ivr_unavailable_audio')
  end

  it 'resolves 127 menu references with eight real inspected versions without a per-menu query or byte read' do
    audio_proof
    versions = [audio_version] + Array.new(7) { other_scope_audio(unit) }
    menu = ivr_definition['nodes'][0]
    ivr_definition['nodes'] = Array.new(127) do |index|
      menu.deep_dup.merge('id' => "menu_#{index}", 'audio_reference' => audio_reference_for(versions[index % versions.length]),
                          'options' => [{ 'digit' => '1', 'target' => index == 126 ? 'end' : "menu_#{index + 1}" }])
    end + [{ 'id' => 'end', 'type' => 'end' }]
    ivr_definition['start'] = 'menu_0'
    small = ivr_definition.deep_dup
    small['nodes'] = [menu.deep_dup.merge('options' => [{ 'digit' => '1', 'target' => 'end' }]), { 'id' => 'end', 'type' => 'end' }]
    small['start'] = 'entry'
    baseline = graph_select_count { described_class.new(small, access: graph_access, unit_id: unit.id) }
    graph = nil
    count = graph_select_count { graph = build_graph }
    expect(graph.nodes.length).to eq(128)
    expect(graph.audio_proofs.length).to eq(8)
    expect(count).to be <= baseline + 2
    expect(graph.audio_proofs.pluck('version_id')).to match_array(versions.map { |version| version.id.to_s })
  end

  def graph_select_count
    count = 0
    callback = ->(_name, _start, _finish, _id, payload) { count += 1 if payload.fetch(:sql).lstrip.start_with?('SELECT') }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      ActiveRecord::Base.uncached { yield }
    end
    count
  end

end
