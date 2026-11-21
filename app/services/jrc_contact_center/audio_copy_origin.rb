# frozen_string_literal: true

require 'tempfile'

class JrcContactCenter::AudioCopyOrigin
  Metadata = Struct.new(:filename, :content_type, :byte_size, :sha256, keyword_init: true)
  AUDIT_FIELDS = %w[source_asset_id source_version_id source_sha256].freeze

  attr_reader :unit_id, :source_kind

  def initialize(access:, asset_id:, version_id:, expected:)
    @access = access
    @asset_id = access.identifier!(asset_id).dup.freeze
    @version_id = access.identifier!(version_id).dup.freeze
    @expected = expected.is_a?(String) ? expected.dup.freeze : expected
    @asset = access.asset(@asset_id)
    @version = access.versions(@asset).find(@version_id)
    @unit_id = @asset.unit_id.to_s.freeze
    @source_kind = @version.source_kind.dup.freeze
    @binding = source_binding.freeze
  end

  def digest_binding
    @binding
  end

  def metadata
    Metadata.new(filename: ActiveStorage::Filename.new(@version.file_name).to_s, content_type: @version.content_type,
                 byte_size: @version.byte_size, sha256: @version.sha256)
  end

  def authorize!(unit)
    @asset = @access.asset(@asset_id)
    @version = @access.versions(@asset).find(@version_id)
    valid = unit.id.to_s == unit_id && @asset.unit_id.to_s == unit_id && @version.sha256 == digest_binding.fetch('source_sha256')
    raise ActiveRecord::RecordNotFound unless valid
  end

  def check_revision!
    JrcContactCenter::AudioAssetRevision.check!(@asset, version: @access.latest(@asset), expected: @expected)
    proof = @access.inspections(@version).order(attempt: :desc).first
    JrcContactCenter::AudioVersionReadiness.check!(version: @version, proof: proof)
  end

  def with_upload
    result = JrcContactCenter::AudioBytes.new(access: @access).call(asset_id: @asset_id, version_id: @version_id)
    Tempfile.create(['jrc-cc-copy-', '.bin']) do |file|
      file.binmode
      file.write(result.bytes)
      file.flush
      file.rewind
      upload = ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: result.file_name, type: result.content_type)
      yield upload
    end
  end

  def record_copy!(version)
    snapshot = JrcContactCenter::ConfigurationAuditSnapshot.capture(version)
    Audited.audit_class.create!(
      auditable: version, associated: @access.account, user: @access.actor, action: 'copy',
      comment: JrcContactCenter::ConfigurationAudit::COMMENT, audited_changes: {
        'attributes' => [nil, snapshot.fetch('attributes')],
        'cc_scope' => { 'before' => nil, 'after' => snapshot.fetch('scope') },
        'omitted_fields' => [], 'schema_version' => 1, 'audio_copy' => digest_binding.slice(*AUDIT_FIELDS)
      }
    )
  end

  private

  def source_binding
    { 'operation' => 'institutional_audio_copy_v1', 'account_id' => @access.account.id.to_s.freeze,
      'unit_id' => unit_id, 'source_asset_id' => @asset_id, 'source_version_id' => @version_id,
      'source_sha256' => @version.sha256.dup.freeze }
  end
end
