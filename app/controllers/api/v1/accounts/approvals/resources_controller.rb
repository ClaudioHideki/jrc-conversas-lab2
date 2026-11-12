class Api::V1::Accounts::Approvals::ResourcesController < Api::V1::Accounts::Approvals::BaseController
  RESOURCE_ACTIONS = %w[request_create policy_manage].freeze
  LABEL_FIELDS = %w[title proposal_number order_number request_number contract_number].freeze

  def index
    key = params[:key].to_s
    allowed = JrcApprovals::CommercialCatalog::EVENTS.key?(key) || JrcApprovals::FinancialCatalog::EVENTS.key?(key) || [JrcApprovals::DraftReviewCatalog::KEY, JrcBackoffice::AuthorityCatalog::KEY,
                                                                    JrcRelationship::DistributionApproval::KEY].include?(key)
    raise JrcApprovals::Error, 'ADAPTER_NOT_INSTALLED' unless allowed

    entry = JrcApprovals::Catalog.fetch(key)
    rows = entry.model.where(account_id: Current.account.id).order(:id).filter_map { |record| resource_payload(entry, record) }
    render json: paginated(rows)
  end

  private

  def resource_payload(entry, record)
    return unless entry.authorize.call(Current.user, record)
    return distribution_payload(record) if entry.key == JrcRelationship::DistributionApproval::KEY

    unit = JrcApprovals::CommercialCatalog.business_unit(record)
    return unless scope_allowed?(unit)

    { id: record.id, label: resource_label(record), issuer_company_id: unit.company_id, business_unit_id: unit.id }
  rescue Pundit::NotAuthorizedError
    nil
  end

  def distribution_payload(record)
    return unless record.state == 'previewed'

    snapshot = JrcRelationship::DistributionApprovalCatalog.capture(record, Current.user)
    company, unit = snapshot.values_at(:issuer_company_id, :business_unit_id)
    return unless RESOURCE_ACTIONS.any? { |action| distribution_scope_allowed?(action, company, unit) }

    { id: record.id, label: "##{record.id} · #{record.inputs['justification'].to_s.first(80)}",
      issuer_company_id: company, business_unit_id: unit }
  rescue ArgumentError, ActiveRecord::RecordNotFound
    nil
  end

  def distribution_scope_allowed?(action, company, unit)
    authorization.authorize!(action, company_id: company, unit_id: unit)
    true
  rescue Pundit::NotAuthorizedError
    false
  end

  def scope_allowed?(unit)
    RESOURCE_ACTIONS.any? do |action|
      authorization.authorize!(action, company_id: unit.company_id, unit_id: unit.id)
      true
    rescue Pundit::NotAuthorizedError
      false
    end
  end

  def resource_label(record)
    label = LABEL_FIELDS.filter_map { |field| record.public_send(field) if record.respond_to?(field) }.first
    label || "#{record.class.model_name.human} ##{record.id}"
  end
end
