require 'rails_helper'

RSpec.describe JrcContactCenter::AudioInspection do
  include_context 'with an institutional audio receipt'

  let(:version) do
    JrcContactCenter::AudioUploads.new(access: JrcContactCenter::AudioLibraryAccess.new(context: context))
                                 .create!(unit_id: unit.id, attributes: { name: 'SYNTHETIC inspected source' }, file: upload, key: key)
  end
  let(:attributes) do
    # Synthetic observation fixture for model/SQL invariants, not an actual scanner or codec proof.
    { account: account, unit_id: unit.id, audio_version: version, source_blob: version.blob, created_by: actor,
      attempt: 1, idempotency_key: 'synthetic-inspection-request-0001', input_digest: 'a' * 64,
      state: 'clean', probe_state: 'valid', scanner_adapter: 'clamav-instream-v1', expected_sha256: version.sha256,
      observed_sha256: version.sha256, decoder_version: 'ffmpeg version SYNTHETIC invariant fixture', observed_at: Time.current,
      metadata: { 'container' => 'wav', 'codec' => 'pcm_s16le', 'content_type' => 'audio/wav', 'duration_ms' => 1,
                  'sample_rate' => 8_000, 'channels' => 1, 'probe_version' => 'ffprobe version SYNTHETIC invariant fixture' } }
  end
  let(:record) { described_class.create!(attributes) }

  def insert_observation(values)
    connection = described_class.connection
    columns = values.keys.map { |name| connection.quote_column_name(name) }.join(', ')
    quoted = values.map { |name, value| connection.quote(described_class.type_for_attribute(name).serialize(value)) }.join(', ')
    connection.execute("INSERT INTO jrc_contact_center_audio_inspections (#{columns}) VALUES (#{quoted})")
  end

  it 'requires a persisted exact-source observation and valid decoder metadata instead of treating an unsaved fixture as clearance' do
    expect(described_class.new(attributes).ready?).to be(false)
    saved = record
    expect(saved.ready?).to be(true)
    expect(saved).to have_attributes(audio_version_id: version.id, source_blob_id: version.blob_id, expected_sha256: version.sha256)
  end

  it 'keeps accepted observations immutable at the model and database levels' do
    saved = record
    expect { saved.update!(state: 'unavailable') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { saved.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect do
      described_class.transaction(requires_new: true) do
        described_class.connection.execute("UPDATE jrc_contact_center_audio_inspections SET state = 'unavailable' WHERE id = #{saved.id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /observations are immutable/)
    expect do
      described_class.transaction(requires_new: true) { described_class.where(id: saved.id).delete_all }
    end.to raise_error(ActiveRecord::StatementInvalid, /observations are immutable/)
    expect(saved.reload.state).to eq('clean')
  end

  it 'rejects missing or mismatched observed hashes instead of accepting a null-valued clean CHECK predicate' do
    value = described_class.new(attributes.merge(observed_sha256: nil))
    expect(value).not_to be_valid
    saved = record
    raw = saved.attributes.except('id').merge('attempt' => 2, 'idempotency_key' => 'synthetic-inspection-request-0002', 'observed_sha256' => nil)
    expect do
      described_class.transaction(requires_new: true) { insert_observation(raw) }
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(saved.reload.observed_sha256).to eq(version.sha256)
  end

  it 'does not admit private tags or locators into metadata even through direct SQL' do
    saved = record
    raw = saved.attributes.except('id').merge('attempt' => 2, 'idempotency_key' => 'synthetic-inspection-request-0002')
    raw['metadata'] = raw['metadata'].merge('private_locator' => 'SYNTHETIC must never be metadata')
    expect do
      described_class.transaction(requires_new: true) { insert_observation(raw) }
    end.to raise_error(ActiveRecord::StatementInvalid, /exact decoded metadata unavailable/)
    expect(saved.reload.metadata.keys.sort).to eq(JrcContactCenter::AudioMediaMetadata::FIELDS.sort)
  end

  it 'binds the native unit, exact version, stored blob and expected hash independently of client-shaped identifiers' do
    saved = record
    raw = saved.attributes.except('id').merge('attempt' => 2, 'idempotency_key' => 'synthetic-inspection-request-0002', 'unit_id' => units.last.id)
    expect do
      described_class.transaction(requires_new: true) { insert_observation(raw) }
    end.to raise_error(ActiveRecord::StatementInvalid, /inspection origin unavailable/)
    expect(saved.reload.unit_id).to eq(unit.id)
    expect(version.reload.blob.download).to eq(bytes)
  end

  it 'keeps unavailable observations as explicit history without any ready status or fabricated media metadata' do
    unavailable = described_class.create!(attributes.merge(state: 'unavailable', probe_state: 'not_run', metadata: {}, decoder_version: nil))
    expect(unavailable.ready?).to be(false)
    expect(unavailable.metadata).to eq({})
    expect(unavailable.decoder_version).to be_nil
  end

  it 'requires actual decoder metadata when a record claims media validation' do
    expect(described_class.new(attributes.merge(state: 'infected'))).not_to be_valid
    expect(described_class.new(attributes.merge(decoder_version: nil))).not_to be_valid
    expect(described_class.new(attributes.merge(metadata: { 'duration_ms' => 1 }))).not_to be_valid
    metadata = attributes.fetch(:metadata).merge('content_type' => 'audio/mpeg')
    expect(described_class.new(attributes.merge(metadata: metadata))).not_to be_valid
  end

  it 'audits the exact unit and technical observation while withholding private blob and request correlators' do
    saved = record
    audit = Audited.audit_class.where(auditable: saved, associated: account).last
    expect(audit.audited_changes.dig('cc_scope', 'after', 'unit_id')).to eq(unit.id.to_s)
    expect(audit.audited_changes.dig('attributes', 1)).to include('audio_version_id' => version.id, 'state' => 'clean', 'probe_state' => 'valid')
    expect(audit.audited_changes.to_json).not_to include(saved.idempotency_key, saved.input_digest, version.blob.key, version.file_name)
    expect(JrcContactCenter::AudioLibraryPresenter.inspection(saved)).not_to have_key('source_blob_id')
    expect(JrcContactCenter::ConfigurationAuditQuery.resource_key(audit)).to eq('audio_inspection')
  end
end
