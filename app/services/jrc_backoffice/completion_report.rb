# A current operational report, not a legal signature certificate or a frozen documentary package.
class JrcBackoffice::CompletionReport
  class NotCompleted < StandardError; end
  class TooLarge < StandardError; end

  def initialize(account:, actor:, request_id:)
    @access = JrcBackoffice::ContractAccess.new(account: account, actor: actor)
    @request_id = request_id
  end

  def call
    record = @access.request(@request_id)
    csv = record.sales_order.with_lock('FOR SHARE') do
      record.with_lock('FOR SHARE') do
        @request = @access.request(record.id)
        raise NotCompleted unless @request.completed? && @request.stage == 'completed' && @request.completed_at

        rows = request_rows + order_rows + contract_rows + document_rows + sla_rows
        JrcServiceDesk::OperationalCsv.generate(%w[section field value], rows)
      end
    end
    @access.request(@request_id)
    @access.contract!(@request) if @request.contract_id
    audit!
    "\uFEFF#{csv}"
  end

  private

  def rows(section, values)
    values.map { |field, value| [section, field, value.respond_to?(:iso8601) ? value.iso8601 : value] }
  end

  def request_rows
    rows('request', { report_generated_at: Time.current, request_number: @request.request_number, title: @request.title,
                      status: @request.status, stage: @request.stage, workflow_version: @request.workflow_version,
                      opened_at: @request.created_at, completed_at: @request.completed_at,
                      responsible: @request.owner.name, open_issues: @request.open_issues.size })
  end

  def order_rows
    order = @request.sales_order
    rows('order', { order_number: order.order_number, status: order.status, total_cents: order.total_cents,
                    monthly_cents: order.monthly_cents })
  end

  def contract_rows
    return [] unless @request.contract_id

    contract = @access.contract!(@request)
    contract.with_lock('FOR SHARE') do
      rows('contract', { contract_number: contract.contract_number, status: contract.status, signature_status: contract.signature_status,
                         starts_on: contract.starts_on, ends_on: contract.ends_on })
    end
  end

  def document_rows
    versions = @request.document_versions.where(account_id: @access.account.id)
                       .select('DISTINCT ON (document_key) jrc_backoffice_document_versions.*').order(:document_key, version: :desc).limit(101)
    raise TooLarge if versions.size > 100

    versions.flat_map do |version|
      scan = JrcBackoffice::DocumentSafety.new(version).current
      rows("document:#{version.document_key}", { version_id: version.id, version: version.version, review_status: version.status,
                                                 sha256: version.sha256, scan_state: scan&.state || 'pending' })
    end
  end

  def sla_rows
    rows('sla', JrcOperations::SlaClock.new(@request).snapshot.slice(:state, :total_due_at, :first_action_due_at,
                                                                     :first_action_at, :paused_seconds))
  end

  def audit!
    JrcCrm::AuditEvent.create!(account: @access.account, actor_type: 'User', actor_id: @access.actor.id,
                               event_type: 'backoffice_completion_report_accessed', resource_type: @request.class.name,
                               resource_id: @request.id, from_value: {}, to_value: {}, metadata: { format: 'csv', schema_version: 1 })
  end
end
