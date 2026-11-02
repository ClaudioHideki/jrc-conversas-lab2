class JrcBackoffice::DocumentPreanalysisJob < ApplicationJob
  queue_as :low

  def perform(version_id)
    version = JrcBackoffice::DocumentVersion.find(version_id)
    request = version.backoffice_request
    # Match document decisions: request first, version second (including FK locks).
    request.with_lock do
      version.with_lock do
        return if version.analysis

        JrcBackoffice::DocumentPreanalysis.new(version).call
        JrcBackoffice::Documents.new(request: request, actor: version.uploaded_by).reflect_analysis!(version)
      end
    end
  end
end
