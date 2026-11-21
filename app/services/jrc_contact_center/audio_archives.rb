# frozen_string_literal: true

require 'zip'
require 'json'
require 'digest'

# Reuses native authorized bytes, never storage locators or provider recordings.
class JrcContactCenter::AudioArchives
  EXTENSIONS = { 'audio/wav' => '.wav', 'audio/mpeg' => '.mp3', 'audio/ogg' => '.ogg', 'audio/mp4' => '.m4a', 'audio/webm' => '.webm' }.freeze
  Result = Struct.new(:bytes, :sha256, :selection_sha256, :account_id, :unit_id, :entry_count, keyword_init: true)

  def initialize(context:)
    @context = context
    @access = JrcContactCenter::AudioLibraryAccess.new(context: context)
  end

  def call(items:)
    @access.refresh!
    request = JrcContactCenter::AudioArchiveInput.new(access: @access).call(items)
    entries = @access.transaction { authorized_entries!(request) }
    payload = archive_bytes(entries)
    @access.transaction { authorized_entries!(request) }
    Result.new(bytes: payload, sha256: Digest::SHA256.hexdigest(payload), selection_sha256: selection_digest(request),
               account_id: @access.account.id.to_s, unit_id: entries.first.fetch('unit_id'), entry_count: entries.length)
  end

  private

  def selection_digest(request)
    Digest::SHA256.hexdigest(JSON.generate(request.map { |row| row.sort.to_h }))
  end

  def authorized_entries!(request)
    entries = request.map { |row| authorized_entry!(row) }
    total = entries.sum { |row| row.fetch('byte_size') }
    valid = entries.pluck('unit_id').uniq.one? && total <= JrcContactCenter::AudioArchiveInput.limits.fetch(:max_bytes)
    raise JrcContactCenter::OperationError, 'institutional_audio_archive_limit_exceeded' unless valid

    entries
  end

  def authorized_entry!(row)
    asset = @access.asset(row.fetch('audio_asset_id'))
    version = @access.versions(asset).find(row.fetch('audio_version_id'))
    proof = @access.inspections(version).order(attempt: :desc).first
    JrcContactCenter::AudioVersionReadiness.check!(version: version, proof: proof)
    valid = proof.id.to_s == row.fetch('inspection_id') && version.sha256 == row.fetch('sha256')
    raise JrcContactCenter::OperationError.new('institutional_audio_archive_source_changed', status: :conflict) unless valid

    row.merge('unit_id' => asset.unit_id.to_s, 'byte_size' => version.byte_size, 'version_number' => version.number,
              'content_type' => version.content_type, 'file_name' => version.file_name, 'asset_name' => asset.name,
              'usage_check' => local_usage_check(asset))
  end

  def local_usage_check(asset)
    count = JrcContactCenter::AudioIvrUsages.new(context: @context, asset_id: asset.id).relation.count
    { 'coverage' => 'current_local_ivr_drafts_only', 'provider_configuration_verified' => false, 'current_local_ivr_drafts' => count }
  end

  def archive_bytes(entries)
    Zip::OutputStream.write_buffer do |output|
      manifest = entries.map { |entry| write_entry!(output, entry) }
      output.put_next_entry('manifesto.json')
      output.write(JSON.generate('schema' => 'jrc-private-audio-archive-v1', 'account_id' => @access.account.id.to_s, 'items' => manifest))
    end.string
  end

  def write_entry!(output, entry)
    result = JrcContactCenter::AudioBytes.new(access: @access).call(
      asset_id: entry.fetch('audio_asset_id'), version_id: entry.fetch('audio_version_id')
    )
    valid = result.sha256 == entry.fetch('sha256') && result.inspection_id == entry.fetch('inspection_id')
    raise JrcContactCenter::OperationError.new('institutional_audio_archive_source_changed', status: :conflict) unless valid

    filename = "audio-#{entry.fetch('audio_asset_id')}-versao-#{entry.fetch('version_number')}#{EXTENSIONS.fetch(result.content_type)}"
    output.put_next_entry(filename)
    output.write(result.bytes)
    entry.merge('archive_name' => filename)
  end
end
