class Api::V1::Accounts::Approvals::DelegationsController < Api::V1::Accounts::Approvals::BaseController
  def index
    rows = JrcApprovals::Delegation.where(account_id: Current.account.id).includes(:policy_version, :principal, :delegate)
                                   .order(:id).filter_map do |record|
      company_id, unit_id = record.policy_version.publication.values_at('issuer_company_id', 'business_unit_id')
      authorization.authorize!('policy_manage', company_id: company_id, unit_id: unit_id)
      record.attributes.slice('id', 'policy_version_id', 'step_code', 'principal_id', 'delegate_id', 'actions',
                              'reason', 'starts_at', 'ends_at', 'revoked_at').merge(
                                'issuer_company_id' => company_id, 'business_unit_id' => unit_id,
                                'principal_name' => record.principal.user.name, 'delegate_name' => record.delegate.user.name,
                                'window_state' => window_state(record)
                              )
    rescue Pundit::NotAuthorizedError
      nil
    end
    render json: paginated(rows)
  end

  def create
    values = params.require(:delegation).permit(:policy_version_id, :step_code, :principal_id, :delegate_id,
                                                :reason, :starts_at, :ends_at, actions: []).to_h.symbolize_keys
    values[:starts_at] = Time.iso8601(values.fetch(:starts_at))
    values[:ends_at] = Time.iso8601(values.fetch(:ends_at))
    record = service(JrcApprovals::Delegations).create!(**values)
    render json: { id: record.id }, status: :created
  rescue ArgumentError
    render json: { error: 'INVALID_DELEGATION_WINDOW' }, status: :unprocessable_entity
  end

  def destroy
    service(JrcApprovals::Delegations).revoke!(id: params[:id])
    head :no_content
  end

  private

  def window_state(record)
    return 'revoked' if record.revoked_at
    return 'scheduled' if record.starts_at > Time.current
    return 'expired' if record.ends_at <= Time.current

    'active'
  end
end
