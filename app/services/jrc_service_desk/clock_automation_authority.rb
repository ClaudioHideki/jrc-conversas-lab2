# frozen_string_literal: true

# The published policy selects one native operator. No role, publisher or global
# operator is inferred as an executor when that explicit selection is absent.
class JrcServiceDesk::ClockAutomationAuthority
  CAPABILITIES = %i[tickets_view tickets_edit sla_view].freeze

  def self.verify!(policy, account:, unit:)
    id = policy.execution_account_user_id
    return unless id

    member = AccountUser.where(account_id: account.id).lock('FOR SHARE').find(id)
    return member unless policy.automatic?

    lock_current_role!(member, account)
    context = JrcServiceDesk::OperationalContext.new(account: account, user: member.user, account_user: member)
    required = CAPABILITIES + (policy.thresholds.any? { |row| row['queue_id'] } ? [:tickets_transfer] : [])
    raise Pundit::NotAuthorizedError unless context.unit_allowed?(unit) && required.all? { |key| context.capability?(key) }

    member
  end

  def self.lock_current_role!(member, account)
    return unless member.respond_to?(:custom_role_id) && member.custom_role_id

    raise Pundit::NotAuthorizedError unless member.custom_role

    member.custom_role.class.where(account_id: account.id, id: member.custom_role_id).lock('FOR SHARE').take!
  end
  private_class_method :lock_current_role!
end
