class Api::V1::Accounts::Approvals::GatesController < Api::V1::Accounts::Approvals::BaseController
  def show
    key = params[:key].to_s
    raise JrcApprovals::Error, 'ADAPTER_NOT_INSTALLED' unless JrcApprovals::CommercialCatalog::EVENTS.key?(key)

    result = service(JrcApprovals::CommercialGate).evaluate(key: key, resource_id: params[:resource_id])
    result[:mode] = JrcApprovals::CommercialGate.mode(Current.account, key)
    Array(result[:requests]).each { |item| item[:readable] = readable?(item[:id]) }
    result[:signature_evidence] = signature_state(key) if key == 'contracts.company_signature'
    render json: result
  end

  private

  def readable?(id)
    record = JrcApprovals::Request.where(account_id: Current.account.id).find(id)
    JrcApprovals::RequestVisibility.authorize!(account: Current.account, user: Current.user, record: record)
    true
  rescue Pundit::NotAuthorizedError
    false
  end

  def signature_state(key)
    snapshot = JrcApprovals::Catalog.snapshot(account: Current.account, user: Current.user, key: key, resource_id: params[:resource_id])
    snapshot['values']['signature_evidence']
  end
end
