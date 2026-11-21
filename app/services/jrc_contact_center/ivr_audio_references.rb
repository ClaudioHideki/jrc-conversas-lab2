# frozen_string_literal: true

# References exact authorized versions in an internal draft, never a PABX codec or publication contract.
class JrcContactCenter::IvrAudioReferences
  def initialize(context:, unit_id:)
    @access = JrcContactCenter::AudioLibraryAccess.new(context: context)
    @unit_id = unit_id
  end

  def call(references)
    validate_size!(references)
    return [] if references.empty?

    selected = references.uniq
    @access.transaction do
      versions = @access.reference_versions(unit_id: @unit_id, asset_ids: selected.pluck('asset_id'), version_ids: selected.pluck('version_id'))
      indexed = versions.index_by { |version| [version.audio_asset_id.to_s, version.id.to_s] }
      selected.map { |reference| verify!(reference, indexed) }
    end
  rescue JrcContactCenter::OperationError => e
    raise unless e.code == 'institutional_audio_not_verified'

    raise JrcContactCenter::OperationError.new('ivr_audio_not_verified', status: :conflict)
  end

  private

  def validate_size!(references)
    valid = references.is_a?(Array) && references.length <= 128
    raise JrcContactCenter::OperationError, 'invalid_ivr_graph' unless valid
  end

  def verify!(reference, versions)
    version = versions[[reference.fetch('asset_id'), reference.fetch('version_id')]]
    valid = version && version.sha256 == reference.fetch('sha256')
    raise JrcContactCenter::OperationError, 'ivr_unavailable_audio' unless valid

    proof = JrcContactCenter::AudioVersionReadiness.check!(version: version, proof: version.latest_inspection)
    { 'asset_id' => version.audio_asset_id.to_s, 'version_id' => version.id.to_s,
      'sha256' => version.sha256, 'inspection_id' => proof.id.to_s }
  end
end
