class Api::V1::Accounts::Approvals::ContextController < Api::V1::Accounts::Approvals::BaseController
  CAPABILITIES = %w[policy_manage request_create decide view_audit].freeze

  def show
    member = authorization.member!
    rows = native_scopes.filter_map do |scope|
      capabilities = authorized_capabilities(scope)
      scope.merge(capabilities: capabilities) if capabilities.any?
    end
    render json: { account_id: Current.account.id, member_id: member.id, scopes: rows }
  end

  private

  def native_scopes
    scopes = [{ issuer_company_id: nil, business_unit_id: nil }]
    JrcCustomers::Company.where(account_id: Current.account.id, relationship_type: 'internal', active: true).find_each do |company|
      scopes << { issuer_company_id: company.id, business_unit_id: nil, company_name: company.name }
      JrcCrm::BusinessUnit.where(account_id: Current.account.id, company_id: company.id, active: true).find_each do |unit|
        scopes << { issuer_company_id: company.id, business_unit_id: unit.id, company_name: company.name, unit_name: unit.name }
      end
    end
    scopes
  end

  def authorized_capabilities(scope)
    CAPABILITIES.select do |action|
      authorization.authorize!(action, company_id: scope[:issuer_company_id], unit_id: scope[:business_unit_id])
      true
    rescue Pundit::NotAuthorizedError
      false
    end
  end
end
