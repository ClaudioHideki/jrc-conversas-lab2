# frozen_string_literal: true

# Atomic folder metadata updates reuse the existing scope, CAS, callbacks and audit.
class JrcContactCenter::AudioAssetMoves
  def initialize(context:)
    @access = JrcContactCenter::AudioLibraryAccess.new(context: context)
  end

  def call(unit_id:, folder_id:, items:)
    request = JrcContactCenter::AudioMoveInput.new(access: @access).call(items)
    @access.transaction do
      unit = @access.unit(unit_id)
      folder = @access.folder(folder_id, unit: unit)
      records = authorized_records!(request, unit)
      records.sort_by(&:id).each { |record| record.update!(folder: folder) unless record.folder_id == folder&.id }
      @access.refresh!
      records.map { |record| JrcContactCenter::AudioLibraryPresenter.asset(record.reload) }
    end
  end

  private

  def authorized_records!(request, unit)
    request.map do |row|
      record = @access.asset(row.fetch('audio_asset_id'))
      raise ActiveRecord::RecordNotFound unless record.unit_id == unit.id

      JrcContactCenter::AudioAssetRevision.check!(record, version: @access.latest(record), expected: row.fetch('expected_revision'))
      record
    end
  end
end
