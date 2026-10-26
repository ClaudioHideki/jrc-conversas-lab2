# frozen_string_literal: true

require 'rails_helper'
require 'json'

RSpec.describe JrcServiceDesk::SupervisionProjection, type: :service do
  include_context 'JRC Service Desk domain'

  def agent_projection(relation)
    described_class.new(context: sd_context, relation: relation)
  end

  def authorized_relation
    JrcServiceDesk::TicketQuery.new(user_context: sd_context).relation
  end

  def assigned_member(unit: sd_unit, active: true)
    member = create(:account_user, account: sd_account, role: :agent)
    create(:jrc_sd_membership, unit: unit, account_user: member, active: active)
  end

  def capture_agent_reads(relation)
    projection = agent_projection(relation)
    statements = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:name] == 'SCHEMA' || payload[:cached]
      next unless payload[:sql].match?(/\ASELECT\b/i)

      statements << payload[:sql]
    end
    rows = nil
    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
        rows = projection.send(:agent_loads)
      end
    end
    [rows, statements]
  end

  before { sd_as_admin! }

  it 'preserves active phase counts, assignee identity and the unassigned bucket' do
    member = assigned_member
    sd_ticket(assignee_membership: member)
    sd_ticket(assignee_membership: member)
    sd_ticket
    waiting = create(:jrc_sd_status, unit: sd_unit, initial: false, phase: 'waiting')
    sd_ticket(assignee_membership: member).update!(status: waiting)
    resolved = create(:jrc_sd_status, unit: sd_unit, initial: false, phase: 'resolved')
    sd_ticket(assignee_membership: member).update!(status: resolved)

    rows = agent_projection(authorized_relation).call.fetch(:by_agent)

    expect(rows).to contain_exactly(
      { id: member.id.to_s, account_user_id: member.account_user_id.to_s, unit_id: sd_unit.id.to_s,
        name: member.account_user.user.name, count: 3 },
      { id: nil, account_user_id: nil, unit_id: nil, name: nil, count: 1 }
    )
  end

  it 'continues showing the existing assignee metadata when the membership is inactive' do
    member = assigned_member
    sd_ticket(assignee_membership: member)
    member.update!(active: false)

    rows, = capture_agent_reads(authorized_relation)

    expect(rows).to eq([
      { id: member.id.to_s, account_user_id: member.account_user_id.to_s, unit_id: sd_unit.id.to_s,
        name: member.account_user.user.name, count: 1 }
    ])
  end

  it 'preserves the Account lookup boundary even if handed a foreign relation internally' do
    foreign = create(:jrc_sd_ticket, unit: sd_foreign_unit)
    member = create(:jrc_sd_membership, unit: sd_foreign_unit)
    foreign.update!(assignee_membership: member)

    rows, = capture_agent_reads(JrcServiceDesk::Ticket.where(id: foreign.id))

    expect(rows).to eq([
      { id: member.id.to_s, account_user_id: nil, unit_id: nil, name: nil, count: 1 }
    ])
  end

  it 'does not include another Account or a filtered-out own unit in the public projection' do
    included = assigned_member
    excluded = assigned_member(unit: sd_other_unit)
    sd_ticket(assignee_membership: included)
    sd_ticket(unit: sd_other_unit, assignee_membership: excluded,
              status: create(:jrc_sd_status, unit: sd_other_unit),
              priority: create(:jrc_sd_priority, unit: sd_other_unit), created_by_membership: excluded)
    create(:jrc_sd_ticket, unit: sd_foreign_unit)
    relation = JrcServiceDesk::TicketQuery.new(user_context: sd_context, parameters: { unit_id: sd_unit.id.to_s }).relation

    rows = agent_projection(relation).call.fetch(:by_agent)

    expect(rows.map { |row| row[:id] }).to eq([included.id.to_s])
    expect(rows.sum { |row| row[:count] }).to eq(1)
  end

  it 'preserves empty and exclusively unassigned projections' do
    empty, = capture_agent_reads(authorized_relation)
    expect(empty).to eq([])
    2.times { sd_ticket }

    rows, = capture_agent_reads(authorized_relation)

    expect(rows).to eq([{ id: nil, account_user_id: nil, unit_id: nil, name: nil, count: 2 }])
  end

  it 'records query counts and real PostgreSQL plans over the same synthetic authorized cohorts' do
    members = 12.times.map { assigned_member }
    members.each { |member| sd_ticket(assignee_membership: member) }
    connection = ActiveRecord::Base.connection
    observations = [1, 4, 12].map do |size|
      relation = authorized_relation.where(assignee_membership_id: members.first(size).map(&:id))
      rows, statements = capture_agent_reads(relation)
      grouped = relation.select('assignee_membership_id, COUNT(*) AS grouped_count').group(:assignee_membership_id)
      plan = connection.select_value("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) #{grouped.to_sql}")
      expect(rows.length).to eq(size)
      expect(rows.sum { |row| row[:count] }).to eq(size)
      expect(statements).not_to be_empty
      { assignees: size, tickets: size, query_count: statements.length,
        group_count_query_count: statements.count { |sql| sql.include?('GROUP BY') },
        membership_query_count: statements.count { |sql| sql.match?(/FROM "jrc_service_desk_unit_memberships"/) },
        account_user_query_count: statements.count { |sql| sql.match?(/FROM "account_users"/) },
        user_query_count: statements.count { |sql| sql.match?(/FROM "users"/) },
        explain_group_query: JSON.parse(plan), dataset_identifiers: members.first(size).map(&:id),
        rows: rows }
    end
    output = ENV['SD_AGENT_LOADS_PROFILE_OUTPUT']
    if output
      raise 'Profile must remain an isolated temporary file' unless output.match?(%r{\A/tmp/sd-agent-loads-[a-z0-9-]+\.json\z})

      File.write(output, JSON.pretty_generate(
        source_sha: Digest::SHA256.file(Rails.root.join('app/services/jrc_service_desk/supervision_projection.rb')).hexdigest,
        database: connection.current_database, rails_env: Rails.env.to_s,
        measurement: 'uncached real SELECTs inside agent_loads; setup/authorization excluded; grouped SELECT plan analyzed',
        transaction_rollback: true, observations: observations
      ))
    end
    expect(observations.map { |row| row[:assignees] }).to eq([1, 4, 12])
    query_counts = observations.map { |row| row[:query_count] }
    expect(query_counts.uniq.length).to eq(1)
    expect(query_counts.max).to be <= 4
  end
end
