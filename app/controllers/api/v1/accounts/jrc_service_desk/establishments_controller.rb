# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::EstablishmentsController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  def index
    authorize :lookup, :index?, policy_class: ::JrcServiceDesk::LookupPolicy
    values = ::JrcServiceDesk::Input.attributes(request.query_parameters, %w[unit_id q])
    context = ::JrcServiceDesk::OperationalContext.new(pundit_user)
    raise Pundit::NotAuthorizedError unless context.capability?(:customers_view)

    authorize :directory, :access?, policy_class: ::JrcCustomers::DirectoryPolicy
    unit = context.unit_scope.find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    enabled = ::JrcServiceDesk::PortalRoutingConfiguration.read(unit)['stores_enabled'] == true
    scope = ::JrcCrm::CorporateCoverage.new(account: Current.account, user: Current.user)
      .companies(::JrcCustomers::EstablishmentMetadata.scope(Current.account))
    query = values.fetch('q', '')
    raise ArgumentError unless query.is_a?(String) && query.size <= 200

    if query.present?
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.strip)}%"
      tax = JrcCustomers::TaxIdentifier.normalize(query)
      tax_pattern = tax.present? ? "%#{ActiveRecord::Base.sanitize_sql_like(tax)}%" : nil
      scope = scope.where("name ILIKE :q OR trade_name ILIKE :q OR tax_id ILIKE :tax OR " \
                            "additional_attributes -> 'jrc_establishment' ->> 'store_code' ILIKE :q", q: pattern, tax: tax_pattern)
    end
    establishments = enabled ? scope.order(:name, :id).limit(100).map { |row| ::JrcCustomers::EstablishmentMetadata.snapshot(row) } : []
    render json: { enabled: enabled, establishments: establishments }
  end
end
