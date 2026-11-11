# frozen_string_literal: true

# Explicit native membership roster, not an email/domain or a company-name match.
class JrcServiceDesk::EmployeeAccess
  READ_CAPABILITIES = %i[module_view tickets_view tickets_create notes_view notes_add history_view sla_view lookups_view customers_view].freeze

  def self.isolated_configurations(context)
    return {} unless context.account && context.account_user

    context.account.internal_attributes.fetch(JrcServiceDesk::InternalIntake::KEY, {}).select do |_id, values|
      values['employee_isolation_enabled'] == true
    end
  end

  def self.configurations(context)
    isolated_configurations(context).select do |_id, values|
      Array(values['employee_account_user_ids']).include?(context.account_user.id)
    end
  end

  def self.registered?(context)
    configurations(context).any?
  end

  def self.restricted?(context)
    return false if context.customer_execution?
    values = isolated_configurations(context)
    return false if values.empty?
    return true if context.employee_portal?

    values.values.none? { |row| Array(row['support_account_user_ids']).include?(context.account_user.id) }
  end

  def self.unit_ids(context)
    configurations(context).keys.map { |id| JrcServiceDesk::Input.id(id) }
  end

  def self.service_ids(context, unit_id: nil)
    rows = configurations(context)
    rows = rows.slice(unit_id.to_s) if unit_id
    rows.values.flat_map { |row| Array(row['internal_service_ids']) }.uniq
  end

  def self.services(scope, context)
    restricted?(context) ? scope.where(id: service_ids(context)) : scope
  end

  def self.catalogue(scope, context)
    return scope unless restricted?(context)
    return scope if context.administrator? && !context.employee_portal?

    services = JrcServiceDesk::Service.where(account_id: context.account.id, id: service_ids(context))
    ids = case scope.klass.name
          when 'JrcServiceDesk::Service' then service_ids(context)
          when 'JrcServiceDesk::Category' then services.select(:default_category_id)
          when 'JrcServiceDesk::TicketType' then services.select(:default_ticket_type_id)
          when 'JrcServiceDesk::Queue' then configurations(context).values.map { |row| row['queue_id'] }
          when 'JrcServiceDesk::Priority'
            return scope.where('LOWER(code) = ? OR LOWER(name) = ?', 'normal', 'normal')
          when 'JrcServiceDesk::TicketStatus'
            return scope.where(initial: true)
          else []
          end
    scope.where(id: ids)
  end

  def self.tickets(scope, context)
    return scope unless restricted?(context)

    links = JrcServiceDesk::TicketEvent.where(account_id: context.account.id, event_type: 'creation_context_recorded')
      .where('data @> ?::jsonb', { internal_request: true }.to_json).select(:ticket_id)
    scope.where(id: links, created_by_membership_id: context.creator_memberships)
  end

  def self.verify_service!(context, unit_id, service_id)
    return unless restricted?(context)
    raise Pundit::NotAuthorizedError unless unit_ids(context).include?(unit_id)
    raise Pundit::NotAuthorizedError if service_id && !service_ids(context, unit_id: unit_id).include?(JrcServiceDesk::Input.id(service_id))
  end

  def self.portal_identity?(user)
    AccountUser.where(user_id: user.id).includes(:account).any? do |member|
      context = JrcServiceDesk::OperationalContext.new(account: member.account, user: user, account_user: member)
      isolated_configurations(context).any?
    end
  end

  def self.portal_context(user)
    members = AccountUser.where(user_id: user.id).includes(:account).select do |member|
      context = JrcServiceDesk::OperationalContext.new(account: member.account, user: user, account_user: member, employee_portal: true)
      member.account.internal_attributes['requester_portal_enabled'] == true && context.available? && registered?(context) && context.capability?(:tickets_create) && context.unit_scope.exists?
    end
    return if members.empty?
    raise JrcServiceDesk::PortalIdentityRequired unless members.one?

    member = members.sole
    JrcServiceDesk::UiContextService.new(user_context: { account: member.account, user: user, account_user: member, employee_portal: true }).call
  end
end
