require 'rails_helper'

RSpec.describe JrcContactCenter::IvrDraftWrite do
  include_context 'with a local IVR audio reference'

  def input_for(definition: ivr_definition, revision: 0, request_id: SecureRandom.uuid, status: 'draft')
    JrcContactCenter::IvrDraftInput.new(
      name: 'SYNTHETIC audio draft', status: status, definition: definition,
      expected_revision: revision, request_id: request_id
    )
  end

  def write_audio_draft(input = input_for)
    described_class.new(context: context).call(input: input, unit_id: unit.id)
  end

  def ledger_counts
    [JrcContactCenter::IvrDraft.count, JrcContactCenter::IvrDraftVersion.count, Audited.audit_class.count]
  end

  it 'persists the exact version, current observation and authenticated audit atomically' do
    proof = audio_proof
    result = write_audio_draft
    audit = Audited.audit_class.find_by!(auditable: result.fetch(:version))
    expect(result.fetch(:version).reload.definition).to eq(ivr_definition)
    expect(audit.user).to eq(actor)
    expect(audit.associated).to eq(account)
    expect(audit.audited_changes.fetch('validated_audio_versions')).to eq(
      [audio_reference_for(audio_version).merge('inspection_id' => proof.id.to_s)]
    )
    expect(audit.audited_changes.to_json).not_to include('SYNTHETIC audio draft', 'blob_id', 'file_name', '"nodes"')
  end

  it 'does not create an identity, revision or audit when audio has not been observed' do
    audio_version
    input = input_for
    before = ledger_counts
    expect { write_audio_draft(input) }.to raise_error(JrcContactCenter::OperationError, 'ivr_audio_not_verified')
    expect(ledger_counts).to eq(before)
  end

  it 'does not commit a partial revision when the audit fails' do
    audio_proof
    input = input_for
    before = ledger_counts
    allow(JrcContactCenter::IvrDraftAudit).to receive(:write!).and_raise(ActiveRecord::RecordInvalid)
    expect { write_audio_draft(input) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(ledger_counts).to eq(before)
  end

  it 'replays the original receipt without silently creating another proof or revision' do
    audio_proof
    input = input_for
    original = write_audio_draft(input)
    before = ledger_counts
    replay = write_audio_draft(input)
    expect(replay).to include(replayed: true, version: original.fetch(:version))
    expect(ledger_counts).to eq(before)
    expect(JrcContactCenter::AudioInspection.where(audio_version: audio_version).count).to eq(1)
  end

  it 'requires current authority even when replaying a previously authorized receipt' do
    audio_proof
    input = input_for
    write_audio_draft(input)
    member.custom_role.update!(permissions: ['jrc_contact_center_view'])
    expect { write_audio_draft(input) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'does not overwrite an accepted pin with a stale revision or a different request hash' do
    audio_proof
    original = write_audio_draft
    changed = input_for(definition: ivr_definition.deep_dup.tap { |graph| graph['nodes'][0].delete('audio_reference') })
    expect do
      described_class.new(context: context).call(input: changed, id: original.fetch(:draft).id)
    end.to raise_error(JrcContactCenter::OperationError, 'stale_ivr_revision')
    expect(original.fetch(:version).reload.definition).to eq(ivr_definition)
    expect(original.fetch(:draft).versions.count).to eq(1)
  end

  it 'allows unlinking explicitly without altering the immutable earlier pin or library version' do
    audio_proof
    original = write_audio_draft
    graph = ivr_definition.deep_dup
    graph['nodes'][0].delete('audio_reference')
    result = described_class.new(context: context).call(input: input_for(definition: graph, revision: 1), id: original.fetch(:draft).id)
    expect(result.fetch(:version).definition).to eq(graph)
    expect(original.fetch(:version).reload.definition).to eq(ivr_definition)
    expect(audio_version.reload).to be_persisted
    expect(Audited.audit_class.find_by!(auditable: result.fetch(:version)).audited_changes).not_to have_key('validated_audio_versions')
  end

  it 'keeps archival possible when current inspection is unavailable without mutating the pinned definition' do
    audio_proof
    original = write_audio_draft
    with_modified_env JRC_CC_AUDIO_CLAMAV_SOCKET: nil do
      JrcContactCenter::AudioInspections.new(access: library).create!(
        asset_id: audio_version.audio_asset_id, version_id: audio_version.id, key: 'synthetic-ivr-archive-unavailable'
      )
    end
    result = described_class.new(context: context).call(input: input_for(revision: 1, status: 'archived'), id: original.fetch(:draft).id)
    expect(result.fetch(:version).status).to eq('archived')
    expect(result.fetch(:version).definition).to eq(ivr_definition)
    expect(original.fetch(:version).reload.status).to eq('draft')
  end
end
