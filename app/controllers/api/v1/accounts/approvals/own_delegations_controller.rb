class Api::V1::Accounts::Approvals::OwnDelegationsController < Api::V1::Accounts::Approvals::BaseController
  def index
    member = authorization.member!
    rows = JrcApprovals::OwnDelegations.grants(Current.account).filter_map do |grant|
      action = if grant.principal_id == member.id
                 'delegate'
               elsif grant.delegate_id == member.id
                 'decide'
               else
                 'policy_manage'
               end
      authorize_read!(grant, action)
      serialize(grant)
    rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
      nil
    end
    render json: paginated(rows)
  end

  def recipients
    company_id = reference(params[:issuer_company_id])
    unit_id = reference(params[:business_unit_id])
    actor = authorization.authorize!('delegate', company_id: company_id, unit_id: unit_id)
    authorization.authorize!('decide', company_id: company_id, unit_id: unit_id)
    render json: paginated(eligible_recipients(company_id, unit_id, actor))
  end

  def create
    input = params.require(:delegation).permit(:delegate_id, :issuer_company_id, :business_unit_id,
                                               :reason, :starts_at, :ends_at, :idempotency_key, actions: []).to_h.symbolize_keys
    %i[delegate_id issuer_company_id business_unit_id].each { |key| input[key] = reference(input[key]) }
    %i[starts_at ends_at].each { |key| input[key] = timestamp(input.fetch(key)) }
    grant = service(JrcApprovals::OwnDelegations).create!(**input)
    render json: serialize(grant), status: :created
  end

  def destroy
    service(JrcApprovals::OwnDelegations).revoke!(id: params[:id])
    head :no_content
  end

  private

  def timestamp(value)
    raise JrcApprovals::Error, 'INVALID_DELEGATION_WINDOW' unless value.is_a?(String) && value.match?(/(?:Z|[+-]\d{2}:\d{2})\z/)

    Time.iso8601(value)
  end

  def authorize_read!(grant, action)
    authorization.authorize!(action, company_id: grant.issuer_company_id, unit_id: grant.business_unit_id)
  rescue Pundit::NotAuthorizedError
    raise if action == 'policy_manage'

    authorization.authorize!('policy_manage', company_id: grant.issuer_company_id, unit_id: grant.business_unit_id)
  end

  def eligible_recipients(company_id, unit_id, actor)
    eligibility = JrcApprovals::Eligibility.new(account: Current.account, company_id: company_id, unit_id: unit_id)
    Current.account.account_users.includes(:user).where.not(id: actor.id).order(:id).filter_map do |member|
      { id: member.id, name: member.user.name } if eligibility.capable?(member)
    end
  end

  def reference(value)
    value.present? ? Integer(value.to_s, 10) : nil
  end

  def serialize(grant)
    { id: grant.id, principal_id: grant.principal_id, delegate_id: grant.delegate_id,
      issuer_company_id: grant.issuer_company_id, business_unit_id: grant.business_unit_id, actions: grant.actions,
      starts_at: grant.starts_at, ends_at: grant.ends_at, reason: grant.record.data.fetch('reason'),
      revoked: grant.revoked?, can_revoke: can_revoke?(grant) }.merge(party_names(grant))
  end

  def can_revoke?(grant)
    service(JrcApprovals::OwnDelegations).authorize_revoke!(grant)
    true
  rescue Pundit::NotAuthorizedError
    false
  end

  def party_names(grant)
    parties = Current.account.account_users.includes(:user).where(id: [grant.principal_id, grant.delegate_id]).index_by(&:id)
    { principal_name: parties.fetch(grant.principal_id).user.name, delegate_name: parties[grant.delegate_id]&.user&.name }
  end
end
