# frozen_string_literal: true

class JrcServiceDesk::ReportExportJob < ApplicationJob
  queue_as :low

  def perform(id)
    export = JrcServiceDesk::ReportExport.find(id)
    claimed = export.with_lock do
      next false unless export.state == 'queued'

      export.update!(state: 'processing')
      true
    end
    return unless claimed

    member = AccountUser.find(export.account_user_id)
    context = { account: member.account, user: member.user, account_user: member }
    transaction_options = ActiveRecord::Base.connection.transaction_open? ? {} : { isolation: :repeatable_read }
    ActiveRecord::Base.transaction(**transaction_options) do
      access = JrcServiceDesk::ReportExportAccess.new(export, context)
      raise ArgumentError, 'Export expired' if export.expires_at <= Time.current
      raise ArgumentError, 'Export limit exceeded' if access.query.relation.count > export.limit

      unless access.query.relation.count == export.expected_count
        raise JrcServiceDesk::IdempotencyConflict,
              'Report changed; refresh before exporting'
      end

      dataset = JrcServiceDesk::ReportExportData.new(access.query)
      artifact = JrcServiceDesk::ReportExportFile.new(dataset, export.format).call
      export.file.attach(io: StringIO.new(artifact.fetch(:data)), filename: artifact.fetch(:filename), content_type: artifact.fetch(:content_type))
      export.update!(state: 'ready', record_count: dataset.count, authorization_signature: access.signature,
                     observed_at: dataset.observed_at, metadata: { 'report_version' => 2, 'timezone' => dataset.timezone,
                                                                   'sha256' => Digest::SHA256.hexdigest(artifact.fetch(:data)) })
      JrcServiceDesk::ReportExportAudit.call(export, 'completed', context[:user])
    end
    JrcServiceDesk::ReportExportCleanupJob.set(wait_until: export.expires_at).perform_later(export.id)
  rescue StandardError => e
    if export
      code = case e
             when Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound then 'access_changed'
             when JrcServiceDesk::IdempotencyConflict then 'report_changed'
             when ArgumentError then 'limit_or_criteria'
             else 'generation_failed'
             end
      export.update!(state: 'failed', error_code: code)
      JrcServiceDesk::ReportExportAudit.call(export, 'failed', export.account_user.user)
      Rails.logger.error("service_desk_export_failed export=#{export.id} class=#{e.class.name}")
    end
  end
end
