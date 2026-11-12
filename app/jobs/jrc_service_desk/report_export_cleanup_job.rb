# frozen_string_literal: true

class JrcServiceDesk::ReportExportCleanupJob < ApplicationJob
  queue_as :low

  def perform(id)
    export = JrcServiceDesk::ReportExport.find_by(id: id)
    return unless export && export.expires_at <= Time.current

    export.file.purge if export.file.attached?
    export.update!(state: 'expired')
  end
end
