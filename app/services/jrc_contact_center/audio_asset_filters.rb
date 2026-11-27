# frozen_string_literal: true

# Receives only the already-authorized native library relation; no client IDs confer authority.
class JrcContactCenter::AudioAssetFilters
  def initialize(records:, source_kind: nil, content_type: nil, inspection_state: nil, purpose: nil)
    @records = purpose_filtered(records, purpose)
    @inspection_state = inspection_state
    @values = { source_kind: filter_value(source_kind, %w[user_upload browser_capture]),
                content_type: filter_value(content_type, JrcContactCenter::AudioMediaMetadata::TYPES.values) }.compact
  end

  def call
    JrcContactCenter::AudioInspectionFilter.new(records: version_filtered, state: @inspection_state).call
  end

  private

  # Purpose is the existing free-text usage field, not a new catalog. Escape
  # wildcard characters so searching a literal % or _ cannot broaden results.
  def purpose_filtered(records, value)
    return records if value.nil? || value == ''

    valid = value.is_a?(String) && value.valid_encoding? && value.length <= 160
    raise JrcContactCenter::OperationError, 'invalid_institutional_audio_filter' unless valid
    return records if value.strip.empty?

    escaped = ActiveRecord::Base.sanitize_sql_like(value.strip)
    records.where('jrc_contact_center_audio_assets.purpose ILIKE ?', "%#{escaped}%")
  end

  def version_filtered
    return @records if @values.empty?

    versions = JrcContactCenter::AudioVersion.where(audio_asset_id: @records.reselect(:id))
                                             .select('DISTINCT ON (jrc_contact_center_audio_versions.audio_asset_id) id')
                                             .order(:audio_asset_id, number: :desc)
    matching = JrcContactCenter::AudioVersion.where(id: versions, **@values).select(:audio_asset_id)
    @records.where(id: matching)
  end

  def filter_value(value, allowed)
    return if value.nil? || value == ''
    return value if value.is_a?(String) && allowed.include?(value)

    raise JrcContactCenter::OperationError, 'invalid_institutional_audio_filter'
  end
end
