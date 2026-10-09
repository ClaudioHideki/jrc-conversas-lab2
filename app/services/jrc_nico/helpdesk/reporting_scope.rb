# frozen_string_literal: true

class JrcNico::Helpdesk::ReportingScope
  KEYS = %w[unit_ids company_ids service_ids ticket_ids assignee_account_user_ids].freeze
  COLUMNS = { 'unit_ids' => :unit_id, 'company_ids' => :company_id, 'service_ids' => :service_id, 'ticket_ids' => :id }.freeze
  attr_reader :filters

  def initialize(context, policy, filters = {})
    @context = context.refresh!
    @policy = policy
    @filters = filters.stringify_keys
    raise Pundit::NotAuthorizedError unless policy.account_id == @context.account.id
    raise ArgumentError, 'Unsupported reporting filters' unless (@filters.keys - KEYS).empty?

    @filters.each_value { |ids| JrcNico::Helpdesk::Definition.ids!(ids) }
  end

  def tickets
    scope = @context.tickets.where(unit_id: @policy.definition.fetch('unit_ids'), company_id: @policy.definition.fetch('company_ids'))
    COLUMNS.each do |key, column|
      next unless filters.key?(key)

      assert_filter!(key, scope, column)
      scope = scope.where(column => filters.fetch(key))
    end
    filters.key?('assignee_account_user_ids') ? assigned_tickets(scope) : scope
  end

  def digest
    JrcNico::Helpdesk::Definition.digest('unit_ids' => @policy.definition.fetch('unit_ids').sort,
                                         'company_ids' => @policy.definition.fetch('company_ids').sort, 'filters' => filters.transform_values(&:sort))
  end

  private

  def assigned_tickets(scope)
    ids = filters.fetch('assignee_account_user_ids')
    actual = @context.account.account_users.where(id: ids).pluck(:id)
    raise Pundit::NotAuthorizedError unless actual.sort == ids.sort

    members = JrcServiceDesk::UnitMembership.where(account_id: @context.account.id, account_user_id: ids)
    scope.where(assignee_membership_id: members.select(:id))
  end

  def assert_filter!(key, scope, column)
    ids = filters.fetch(key)
    allowed = if key == 'service_ids'
                Pundit.policy_scope!(@context.native.to_h, JrcServiceDesk::Service)
                      .where(unit_id: @policy.definition.fetch('unit_ids'), id: ids).pluck(:id)
              elsif %w[unit_ids company_ids].include?(key)
                @policy.definition.fetch(key)
              else
                scope.where(column => ids).distinct.pluck(column)
              end
    raise Pundit::NotAuthorizedError unless (ids - allowed).empty?
  end
end
