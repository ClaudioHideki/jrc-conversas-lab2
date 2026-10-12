class Api::V1::Accounts::Approvals::CatalogsController < Api::V1::Accounts::Approvals::BaseController
  def index
    authorization.authorize!('policy_manage', company_id: params[:issuer_company_id].presence&.to_i,
      unit_id: params[:business_unit_id].presence&.to_i)
    rows = (JrcApprovals::CommercialCatalog::EVENTS.keys + [JrcApprovals::CommercialCatalog::PRICE_FAMILY]).map do |key|
      entry = JrcApprovals::Catalog.fetch(key)
      { key: key, version: entry.version, fields: entry.fields, resource_type: entry.model&.name, policy_only: entry.policy_only }
    end
    render json: rows
  end
end
