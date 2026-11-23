# frozen_string_literal: true

class JrcCulture::Roster
  def initialize(access)
    @access = access
  end

  def enable!(unit:, member:, department:)
    unit = @access.admin_units.find(unit.id)
    member = @access.eligible_member!(unit, member.id)
    grant = JrcCulture::Grant.find_or_initialize_by(account: @access.account, member_key: member.id, unit: unit, role: 'employee')
    grant.account_user = member if grant.new_record?
    grant.update!(active: true, department: department.to_s.strip)
    JrcCulture::Event.record!(@access, 'employee_enabled', grant)
    @access.version_scope.published.where(id: JrcCulture::Audience.where(unit: unit).select(:version_id)).find_each do |version|
      JrcCulture::Participations.enroll!(version, JrcCulture::Grant.where(id: grant.id))
    end
    grant
  end

  def disable!(id)
    grant = JrcCulture::Grant.where(account: @access.account, role: 'employee', unit_id: @access.admin_units.select(:id)).find(id)
    grant.update!(active: false)
    JrcCulture::Event.record!(@access, 'employee_disabled', grant)
  end
end
