# frozen_string_literal: true

# This receives the already authorized library relation; scanner results never grant byte access.
class JrcContactCenter::AudioInspectionFilter
  def initialize(records:, state: nil)
    @records = records
    @state = state
    allowed = %w[no_file uninspected] + JrcContactCenter::AudioInspection::STATES
    valid = state.nil? || state == '' || (state.is_a?(String) && allowed.include?(state))
    raise JrcContactCenter::OperationError, 'invalid_institutional_audio_filter' unless valid
  end

  def call
    return @records if @state.nil? || @state == ''
    return @records.where.not(id: all_versions.select(:audio_asset_id)) if @state == 'no_file'

    versions = current_versions
    matching = if @state == 'uninspected'
                 versions.where.not(id: JrcContactCenter::AudioInspection.where(audio_version_id: versions.select(:id)).select(:audio_version_id))
               else
                 versions.where(id: current_inspections(versions).where(state: @state).select(:audio_version_id))
               end
    @records.where(id: matching.select(:audio_asset_id))
  end

  private

  def all_versions
    JrcContactCenter::AudioVersion.where(audio_asset_id: @records.reselect(:id))
  end

  def current_versions
    latest = all_versions.select('DISTINCT ON (jrc_contact_center_audio_versions.audio_asset_id) id')
    latest = latest.order(:audio_asset_id, number: :desc)
    JrcContactCenter::AudioVersion.where(id: latest)
  end

  def current_inspections(versions)
    latest = JrcContactCenter::AudioInspection.where(audio_version_id: versions.select(:id))
                                            .select('DISTINCT ON (jrc_contact_center_audio_inspections.audio_version_id) id')
                                            .order(:audio_version_id, attempt: :desc)
    JrcContactCenter::AudioInspection.where(id: latest)
  end
end
