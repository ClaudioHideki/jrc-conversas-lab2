# A master customer alone is not proof of go-live. Use the existing commercial
# records and the same eligibility for new events and historical backfill.
class JrcRelationship::Eligibility
  def initialize(order)
    @order = order
  end

  def reason
    return 'feature_disabled' unless @order.account.feature_enabled?('jrc_relationship') && @order.account.feature_enabled?('jrc_customer_master')
    config = JrcRelationship::Configuration.find_by(account: @order.account, scope_key: 'account')
    return 'auto_handoff_disabled' if config && !config.effective_rules['auto_handoff']
    return 'order_not_approved' unless JrcCrm::OrderWorkflowSyncService::QUALIFYING_STATUSES.include?(@order.status)
    return 'customer_missing' unless @order.contact || @order.deal&.company
    if JrcCrm::OrderContractService.new(order: @order).required? && !@order.contracts.where(signature_status: 'signed').exists?
      return 'signature_pending'
    end
    requests = @order.backoffice_requests.where(request_kind: 'fulfillment')
    project_ids = requests.pluck(Arel.sql("metadata ->> 'implementation_project_id'")).compact
    projects = JrcProjects::Project.where(account: @order.account).where(id: project_ids).or(
      JrcProjects::Project.where(account: @order.account, idempotency_key: "crm-order-implementation-#{@order.id}"))
    return 'implementation_pending' if projects.where.not(status: 'completed').exists?
    go_live = @order.completed? || requests.where(stage: 'completed', status: 'completed').exists? || projects.where(status: 'completed').exists?
    return 'go_live_pending' unless go_live
    nil
  end

  def identity
    company_id = @order.contact&.company_id || @order.deal&.company_id
    company_id ? { company_id: company_id } : { contact_id: @order.contact_id }
  end
end
