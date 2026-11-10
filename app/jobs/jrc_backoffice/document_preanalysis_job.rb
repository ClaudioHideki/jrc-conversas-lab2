class JrcBackoffice::DocumentPreanalysisJob < ApplicationJob
  queue_as :low
  retry_on JrcBackoffice::DocumentSafety::ScannerUnavailable, wait: 30.seconds, attempts: 3

  def perform(version_id)
    version = JrcBackoffice::DocumentVersion.find(version_id)
    # Commit the technical observation before a parser failure or retry.
    safety = JrcBackoffice::DocumentSafety.new(version).scan!
    raise JrcBackoffice::DocumentSafety::ScannerUnavailable if safety.state == 'unavailable'
    return unless safety.clean?

    request = version.backoffice_request
    # Match document decisions: request first, version second (including FK locks).
    request.with_lock do
      version.with_lock do
        next if version.analysis

        JrcBackoffice::DocumentPreanalysis.new(version).call
        JrcBackoffice::Documents.new(request: request, actor: nil).reflect_analysis!(version)
      end
    end
  end
end
