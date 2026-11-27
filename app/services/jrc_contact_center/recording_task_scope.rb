# frozen_string_literal: true

# Reuse current recording/call access and historical corporate coverage. Native
# Project authorization is checked independently before revealing any target.
class JrcContactCenter::RecordingTaskScope < JrcContactCenter::QualityReviewScope
  private

  def scope_json(_side)
    'jrc_contact_center_recording_task_links.scope_snapshot'
  end
end
