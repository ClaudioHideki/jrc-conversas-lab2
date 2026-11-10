class Api::V1::Accounts::Approvals::CatalogsController < Api::V1::Accounts::Approvals::BaseController
  def index
    authorization.authorize!('policy_manage', company_id: params[:issuer_company_id].presence&.to_i,
                                              unit_id: params[:business_unit_id].presence&.to_i)
    keys = JrcApprovals::CommercialCatalog::EVENTS.keys + JrcApprovals::FinancialCatalog::EVENTS.keys + JrcApprovals::GratuityCatalog::EVENTS.keys + [
      JrcApprovals::DraftReviewCatalog::KEY, JrcApprovals::CommercialCatalog::PRICE_FAMILY, JrcApprovals::GratuityCatalog::FAMILY, JrcBackoffice::AuthorityCatalog::KEY,
      JrcRelationship::DistributionApproval::KEY
    ]
    rows = keys.map do |key|
      entry = JrcApprovals::Catalog.fetch(key)
      { key: key, version: entry.version, fields: entry.fields, resource_type: entry.model&.name, policy_only: entry.policy_only, adjustment_fields: JrcApprovals::AdjustmentPolicy::SOURCES.fetch(key, []) }
    end
    render json: rows
  end
end
