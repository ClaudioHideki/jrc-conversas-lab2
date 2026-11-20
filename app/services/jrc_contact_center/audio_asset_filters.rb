# frozen_string_literal: true

# Receives only the already-authorized native library relation; no client IDs confer authority.
class JrcContactCenter::AudioAssetFilters
  def initialize(records:, source_kind: nil, content_type: nil)
    @records = records
    @values = { source_kind: filter_value(source_kind, %w[user_upload browser_capture]),
                content_type: filter_value(content_type, JrcContactCenter::AudioMediaMetadata::TYPES.values) }.compact
  end

  def call
    return @records if @values.empty?

    versions = JrcContactCenter::AudioVersion.where(audio_asset_id: @records.reselect(:id))
                                             .select('DISTINCT ON (jrc_contact_center_audio_versions.audio_asset_id) id')
                                             .order(:audio_asset_id, number: :desc)
    matching = JrcContactCenter::AudioVersion.where(id: versions, **@values).select(:audio_asset_id)
    @records.where(id: matching)
  end

  private

  def filter_value(value, allowed)
    return if value.nil? || value == ''
    return value if value.is_a?(String) && allowed.include?(value)

    raise JrcContactCenter::OperationError, 'invalid_institutional_audio_filter'
  end
end
