# frozen_string_literal: true

# Explicit department grants intersect native capabilities; they never confer a role.
# The persistent membership marker prevents revocation from restoring broad team access.
class JrcServiceDesk::SupervisionAccess
  PERMISSIONS = (JrcServiceDesk::Capabilities::KEYS - %w[tickets_view_all structure_view operator_companies_manage units_manage
                                                       unit_memberships_manage] + %w[reports_view reports_export]).freeze

  def initialize(context)
    @context = context
  end

  def memberships
    return JrcServiceDesk::UnitMembership.none unless @context.available?

    JrcServiceDesk::UnitMembership.operational.where(account_id: @context.account.id, account_user_id: @context.account_user.id,
                                                    restricted_supervision: true)
  end

  def restricted_units
    memberships.select(:unit_id)
  end

  def restricted?(unit_id)
    memberships.exists?(unit_id: unit_id)
  end

  def grants(permission = 'tickets_view')
    memberships.where(active: true).flat_map do |member|
      normalized = self.class.normalize(member.supervision_grants)
      normalized.filter_map do |grant|
        next unless grant.is_a?(Hash) && grant['permissions'].is_a?(Array) && grant['permissions'].include?('tickets_view') &&
                    grant['permissions'].include?(permission.to_s)

        queue = JrcServiceDesk::Queue.find_by(account_id: @context.account.id, unit_id: member.unit_id, id: grant['queue_id'], active: true)
        next unless queue&.team_id && queue.team_id.to_s == grant['team_id'].to_s &&
                    Team.exists?(id: queue.team_id, account_id: @context.account.id)

        { unit_id: member.unit_id, queue_id: queue.id, team_id: queue.team_id }
      end
    rescue ArgumentError, KeyError
      []
    end
  end

  def any?(permission)
    grants(permission).any?
  end

  def allowed?(ticket, permission)
    return true unless restricted?(ticket.unit_id)
    return false unless ticket.account_id == @context.account.id && ticket.queue_id && ticket.team_id

    grants(permission).any? { |grant| grant == { unit_id: ticket.unit_id, queue_id: ticket.queue_id, team_id: ticket.team_id } }
  end

  # SQL EXISTS is deliberately correlated by Account, Unit, Queue AND Team.
  # Comparing IDs as text safely rejects malformed legacy JSON without unsafe casts.
  # jsonb_exists also keeps embedded scope SQL compatible with Rails positional binds.
  def scope(records, permission: 'tickets_view')
    return records.none unless @context.available?

    unrestricted = records.where.not(unit_id: restricted_units)
    permitted = records.where(<<~SQL.squish, account: @context.account.id, member: @context.account_user.id, permission: permission.to_s)
      EXISTS (
        SELECT 1 FROM jrc_service_desk_unit_memberships supervision_membership
        CROSS JOIN LATERAL jsonb_array_elements(supervision_membership.supervision_grants) AS supervision_grant
        INNER JOIN jrc_service_desk_queues supervision_queue
          ON supervision_queue.id::text = supervision_grant->>'queue_id'
          AND supervision_queue.account_id = supervision_membership.account_id
          AND supervision_queue.unit_id = supervision_membership.unit_id
          AND supervision_queue.active = TRUE
        INNER JOIN teams supervision_team ON supervision_team.id = supervision_queue.team_id
          AND supervision_team.account_id = supervision_membership.account_id
        WHERE supervision_membership.account_id = :account AND supervision_membership.account_user_id = :member
          AND supervision_membership.active = TRUE AND supervision_membership.administrative_actor = FALSE
          AND supervision_membership.restricted_supervision = TRUE
          AND supervision_membership.unit_id = jrc_service_desk_tickets.unit_id
          AND supervision_queue.id = jrc_service_desk_tickets.queue_id
          AND supervision_queue.team_id = jrc_service_desk_tickets.team_id
          AND supervision_queue.team_id::text = supervision_grant->>'team_id'
          AND jsonb_typeof(supervision_grant) = 'object'
          AND jsonb_typeof(supervision_grant->'permissions') = 'array'
          AND jsonb_exists(supervision_grant->'permissions', 'tickets_view')
          AND jsonb_exists(supervision_grant->'permissions', :permission)
      )
    SQL
    unrestricted.or(permitted)
  end

  def self.normalize(value)
    raise ArgumentError, 'Explicit supervision grants required' unless value.is_a?(Array) && value.length <= 100

    result = value.map do |row|
      data = JrcServiceDesk::Input.attributes(row, %w[queue_id team_id permissions])
      permissions = data.fetch('permissions')
      unless permissions.is_a?(Array) && permissions.uniq == permissions && permissions.include?('tickets_view') &&
             (permissions - PERMISSIONS).empty?
        raise ArgumentError, 'Unsupported supervision permissions'
      end

      { 'queue_id' => JrcServiceDesk::Input.id(data.fetch('queue_id')), 'team_id' => JrcServiceDesk::Input.id(data.fetch('team_id')),
        'permissions' => permissions.sort }
    end
    raise ArgumentError, 'Duplicate supervision queue' unless result.map { |row| row['queue_id'] }.uniq.length == result.length

    result
  end
end
