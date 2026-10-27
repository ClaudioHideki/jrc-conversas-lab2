# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk response-local projection' do
  include_context 'JRC Service Desk domain'

  it 'preserves every ticket field and permission for agents and administrators' do
    ticket = sd_ticket(assignee_membership: sd_membership)
    [false, true].each do |admin|
      sd_as_admin! if admin
      expected = JrcServiceDesk::Presenter.new(user_context: sd_context).ticket(ticket)
      actual = JrcServiceDesk::Presenter.new(user_context: sd_context, read_only: true).ticket(ticket)
      expect(actual).to eq(expected)
    end
  end

  it 'loads the authenticated identity a bounded number of times for a page' do
    tickets = Array.new(5) { sd_ticket }
    presenter = JrcServiceDesk::Presenter.new(user_context: sd_context, read_only: true)
    identity_loads = []
    callback = lambda do |*args|
      event = ActiveSupport::Notifications::Event.new(*args)
      identity_loads << event.payload[:sql] if event.payload[:sql].match?(/FROM "(?:users|accounts|account_users)"/)
    end
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { tickets.each { |ticket| presenter.ticket(ticket) } }
    expect(identity_loads.length).to be < 120
  end

  it 'removes repeated database checks when rendering the same twenty-ticket page' do
    tickets = Array.new(20) { sd_ticket }
    measurements = {}
    responses = {}
    [[:legacy, false], [:optimized, true]].each do |label, read_only|
      queries = 0
      callback = ->(*args) { queries += 1 unless ActiveSupport::Notifications::Event.new(*args).payload[:name] == 'SCHEMA' }
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ActiveRecord::Base.cache do
        ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
          presenter = JrcServiceDesk::Presenter.new(user_context: sd_context, read_only: read_only)
          responses[label] = tickets.map { |ticket| presenter.ticket(ticket) }
        end
      end
      measurements[label] = { queries: queries, ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round }
    end
    RSpec.configuration.reporter.message("Read projection benchmark (synthetic local data): #{measurements.to_json}")
    expect(responses[:optimized]).to eq(responses[:legacy])
    expect(measurements[:optimized][:queries]).to be < measurements[:legacy][:queries] * 0.4
  end

  it 'denies foreign and ungranted unit tickets even after presenting an allowed ticket' do
    presenter = JrcServiceDesk::Presenter.new(user_context: sd_context, read_only: true)
    presenter.ticket(sd_ticket)
    [sd_other_unit, sd_foreign_unit].each do |unit|
      hidden = create(:jrc_sd_ticket, unit: unit)
      expect { presenter.ticket(hidden) }.to raise_error(Pundit::NotAuthorizedError)
    end
  end

  it 'refreshes membership on the next response and leaves write policies fresh' do
    ticket = sd_ticket
    reader = JrcServiceDesk::Presenter.new(user_context: sd_context, read_only: true)
    expect(reader.ticket(ticket)[:permissions][:show]).to be(true)
    write_policy = JrcServiceDesk::TicketPolicy.new(sd_context, ticket)
    expect(write_policy.update?).to be(true)
    sd_membership.update!(active: false)
    expect(write_policy.update?).to be(false)
    expect { JrcServiceDesk::Presenter.new(user_context: sd_context, read_only: true).ticket(ticket) }
      .to raise_error(Pundit::NotAuthorizedError)
  end

  it 'refreshes feature access on the next response' do
    ticket = sd_ticket
    JrcServiceDesk::Presenter.new(user_context: sd_context, read_only: true).ticket(ticket)
    sd_account.disable_features!('jrc_service_desk')
    expect { JrcServiceDesk::Presenter.new(user_context: sd_context, read_only: true).ticket(ticket) }
      .to raise_error(Pundit::NotAuthorizedError)
  end

  it 'preserves restricted supervision permissions without granting unrelated actions' do
    team = create(:team, account: sd_account)
    queue = create(:jrc_sd_queue, unit: sd_unit, team: team)
    sd_membership.update!(restricted_supervision: true,
                          supervision_grants: [{ queue_id: queue.id, team_id: team.id, permissions: %w[tickets_view history_view] }])
    ticket = sd_ticket(queue: queue, team: team)
    expected = JrcServiceDesk::Presenter.new(user_context: sd_context).ticket(ticket)
    actual = JrcServiceDesk::Presenter.new(user_context: sd_context, read_only: true).ticket(ticket)
    expect(actual).to eq(expected)
    expect(actual[:permissions]).to include(view_history: true, update: false, view_sla: false, view_customer: false)
    sd_membership.update!(supervision_grants: [])
    expect { JrcServiceDesk::Presenter.new(user_context: sd_context, read_only: true).ticket(ticket) }
      .to raise_error(Pundit::NotAuthorizedError)
  end

  it 'preserves custom role restrictions and refreshes changed role permissions on the next response' do
    role = CustomRole.create!(account: sd_account, name: 'Synthetic service desk reader',
                              permissions: %w[jrc_service_desk_module_view jrc_service_desk_tickets_view jrc_service_desk_tickets_edit])
    sd_account_user.update!(custom_role: role)
    ticket = sd_ticket
    expected = JrcServiceDesk::Presenter.new(user_context: sd_context).ticket(ticket)
    actual = JrcServiceDesk::Presenter.new(user_context: sd_context, read_only: true).ticket(ticket)
    expect(actual).to eq(expected)
    expect(actual[:permissions]).to include(update: true, destroy: false, view_customer: false)
    role.update!(permissions: %w[jrc_service_desk_module_view jrc_service_desk_tickets_view])
    refreshed = JrcServiceDesk::Presenter.new(user_context: sd_context, read_only: true).ticket(ticket)
    expect(refreshed[:permissions][:update]).to be(false)
  end

  it 'does not cache permissions in the default presenter used after commands' do
    ticket = sd_ticket
    presenter = JrcServiceDesk::Presenter.new(user_context: sd_context)
    presenter.ticket(ticket)
    sd_membership.update!(active: false)
    expect { presenter.ticket(ticket) }.to raise_error(Pundit::NotAuthorizedError)
  end
end
