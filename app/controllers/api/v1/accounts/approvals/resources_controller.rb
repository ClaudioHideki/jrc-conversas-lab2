class Api::V1::Accounts::Approvals::ResourcesController < Api::V1::Accounts::Approvals::BaseController
  RESOURCE_ACTIONS = %w[request_create policy_manage].freeze
  LABEL_FIELDS = %w[title proposal_number order_number request_number contract_number].freeze

  def index
    key = params[:key].to_s
    raise JrcApprovals::Error, 'ADAPTER_NOT_INSTALLED' unless JrcApprovals::CommercialCatalog::EVENTS.key?(key)

    entry = JrcApprovals::Catalog.fetch(key)
    rows = entry.model.where(account_id: Current.account.id).order(:id).filter_map { |record| resource_payload(entry, record) }
    render json: paginated(rows)
  end

  private

  def resource_payload(entry, record)
    return unless entry.authorize.call(Current.user, record)

    unit = JrcApprovals::CommercialCatalog.business_unit(record)
    return unless scope_allowed?(unit)

    { id: record.id, label: resource_label(record), issuer_company_id: unit.company_id, business_unit_id: unit.id }
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
