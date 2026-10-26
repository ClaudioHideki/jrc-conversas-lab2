# frozen_string_literal: true

# Operational management projection over official memberships, never contacts/requesters.
class JrcServiceDesk::AssigneesDirectory
  FIELDS = %w[page q unit_id team_id queue_id active auto_assignment_enabled presence].freeze

  def initialize(account:, parameters:)
    @account = account
    @filters = JrcServiceDesk::Input.attributes(parameters, FIELDS).reject { |_key, value| value.nil? || value == '' }
    @page = JrcServiceDesk::Input.id(@filters.fetch('page', 1))
    raise ArgumentError if @page > 1_000_000

    @presence = OnlineStatusTracker.live_presence(account.id)
  end

  def call
    rows = relation
    members = rows.order('users.name ASC', 'jrc_service_desk_unit_memberships.id ASC').offset((@page - 1) * 25).limit(25)
                  .includes(:unit, :team, :queue, account_user: :user).to_a
    loads = JrcServiceDesk::RecordWithdrawal.excluding(JrcServiceDesk::Ticket.where(account_id: @account.id), :ticket)
      .where(assignee_membership_id: members.map(&:id)).joins(:status)
      .where(jrc_service_desk_ticket_statuses: { phase: %w[open waiting] }).group(:assignee_membership_id).count
    { items: members.map { |member| project(member, loads.fetch(member.id, 0)) },
      meta: { page: @page, per_page: 25, total: rows.count }, presence_reason: @presence[:reason] }
  end

  private

  def relation
    rows = JrcServiceDesk::UnitMembership.operational.where(account_id: @account.id).joins(account_user: :user)
    %w[unit_id team_id queue_id].each do |key|
      rows = rows.where(key => JrcServiceDesk::Input.id(@filters[key])) if @filters[key]
    end
    %w[active auto_assignment_enabled].each do |key|
      next unless @filters[key]

      raise ArgumentError unless %w[true false].include?(@filters[key].to_s)

      table = key == 'active' ? 'jrc_service_desk_unit_memberships' : 'account_users'
      rows = rows.where(table => { key => @filters[key].to_s == 'true' })
    end
    if @filters['presence']
      raise ArgumentError unless %w[online offline].include?(@filters['presence'])

      online = @presence[:user_ids]
      rows = @filters['presence'] == 'online' ? rows.where(account_users: { user_id: online }) : rows.where.not(account_users: { user_id: online })
    end
    if @filters['q']
      query = @filters['q']
      raise ArgumentError unless query.is_a?(String) && query.length <= 200

      rows = rows.where('users.name ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
    end
    rows
  end

  def project(member, load)
    ticket = JrcServiceDesk::Ticket.new(account: @account, unit: member.unit, queue: member.queue, team: member.team)
    { id: member.id.to_s, account_user_id: member.account_user_id.to_s, user_id: member.account_user.user_id.to_s,
      name: member.account_user.user.name, unit: named(member.unit), team: named(member.team), queue: named(member.queue),
      record: JrcServiceDesk::StructureRecords.project('unit_memberships', member), load: load,
      effective_presence: @presence[:user_ids].include?(member.account_user.user_id), configured_availability: member.account_user.availability,
      auto_assignment_enabled: member.account_user.auto_assignment_enabled?,
      ineligibility_reason: JrcServiceDesk::AssignmentEligibility.new(membership: member, ticket: ticket, presence: @presence).reason }
  end

  def named(record)
    record && { id: record.id.to_s, name: record.name }
  end
end
