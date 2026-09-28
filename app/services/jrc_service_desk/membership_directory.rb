# frozen_string_literal: true

# Read projection for the existing structural authority. No access is granted here.
class JrcServiceDesk::MembershipDirectory
  def initialize(account:, unit:)
    @account = account
    @unit = unit
  end

  def project(members)
    memberships = if @unit
                    JrcServiceDesk::UnitMembership.where(account: @account, unit: @unit, account_user_id: members.map(&:id))
                                                  .index_by(&:account_user_id)
                  else
                    {}
                  end
    result = { items: members.map { |member| member_data(member, memberships[member.id]) } }
    if @unit
      result[:unit] = JrcServiceDesk::StructureRecords.project('units', @unit)
      result[:operator_company] = JrcServiceDesk::StructureRecords.project('operator_companies', @unit.operator_company)
    end
    result
  end

  private

  def member_data(member, membership)
    context = JrcServiceDesk::OperationalContext.new(account: @account, user: member.user, account_user: member)
    role = context.account_user.respond_to?(:custom_role) ? context.account_user.custom_role : nil
    role = nil unless role&.account_id == @account.id
    {
      id: member.id.to_s, user_id: member.user_id.to_s, name: member.user.name, role: member.role,
      custom_role: role && { id: role.id.to_s, name: role.name }, capabilities: context.effective_capabilities,
      membership: membership && JrcServiceDesk::StructureRecords.project('unit_memberships', membership)
    }
  end
end
