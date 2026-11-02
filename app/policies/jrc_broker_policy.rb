class JrcBrokerPolicy < ApplicationPolicy
  def manage?
    current_member? && account_user.reload.administrator?
  end

  def status?
    allowed?(:status)
  end

  def pair?
    allowed?(:pair)
  end

  def disconnect?
    allowed?(:disconnect)
  end

  def confirm_identity?
    allowed?(:confirm_identity)
  end

  private

  def current_member?
    user.is_a?(User) && account.active? && account_user.present? &&
      AccountUser.exists?(id: account_user.id, account_id: account.id, user_id: user.id)
  end

  def allowed?(action)
    JrcBrokerInboxBinding.uncached do
      return false unless current_member? && record.is_a?(JrcBrokerInboxBinding) && record.account_id == account.id
      # A remote request can finish after this binding was removed or replaced.
      return false unless JrcBrokerInboxBinding.exists?(id: record.id, account_id: account.id, inbox_id: record.inbox_id,
                                                      integration_id: record.integration_id, instance_id: record.instance_id)

      assigned = InboxMember.exists?(inbox_id: record.inbox_id, user_id: user.id)
      can_pair = JrcBrokerInboxGrant.exists?(account_id: account.id, inbox_id: record.inbox_id, user_id: user.id, can_pair: true)
      JrcBroker::Access.allowed?(administrator: account_user.reload.administrator?, assigned: assigned, can_pair: can_pair, action: action)
    end
  end
end
