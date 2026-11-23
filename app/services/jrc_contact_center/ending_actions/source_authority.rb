# frozen_string_literal: true

# Rechecked for each destination attempt under ExecutionTransaction. An immutable
# origin identifies a source; neither it nor a historical scope grants access.
class JrcContactCenter::EndingActions::SourceAuthority
  def initialize(account:, member:)
    @account = account
    @member = JrcOperations::Access.refresh(member)
  end

  def call(origin)
    authorize_actor!(origin)
    access = JrcContactCenter::AccessScope.new(user_context: context)
    raise Pundit::NotAuthorizedError unless access.policy.operate?

    queue = access.queues.includes(:unit).find(origin.queue_id)
    authorize_scope!(origin, queue)
    call = access.my_call_sessions.find(origin.call_session_id)
    call.legs.where(account: @account, account_user: @member).find(origin.call_leg_id)
    call
  end

  private

  def context
    { account: @account, account_user: @member, user: @member.user }
  end

  def authorize_actor!(origin)
    allowed = @member && @member.account_id == @account.id && origin.account_id == @account.id &&
              @member.id == origin.actor_account_user_id && @member.user_id == origin.actor_user_id &&
              @member.user.reload.active_for_authentication?
    raise Pundit::NotAuthorizedError unless allowed
  end

  def authorize_scope!(origin, queue)
    latest = JrcContactCenter::EndingActionQueueScope.where(account: @account, source_queue_id: queue.id).order(revision: :desc).first!
    current = queue.status == 'active' && queue.unit.status == 'active' && latest.scope_state == 'mapped' &&
              latest.id == origin.queue_scope_version_id && latest.unit_id == queue.unit_id && origin.unit_id == queue.unit_id
    raise JrcContactCenter::OperationError, 'ending_action_source_scope_changed' unless current

    links = { 'issuer_company_id' => origin.issuer_company_id&.to_s, 'business_unit_id' => origin.business_unit_id&.to_s }
    JrcContactCenter::OrganizationalScope.new(account: @account, account_user: @member).authorize_links!(links)
  end
end
