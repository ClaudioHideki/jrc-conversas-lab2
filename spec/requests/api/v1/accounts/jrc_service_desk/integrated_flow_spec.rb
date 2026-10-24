# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Integrated Service Desk assignment, clocks and indicators', type: :request do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  include ActiveSupport::Testing::TimeHelpers

  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:agent_a) { create(:account_user, account: sd_account, role: :agent) }
  let(:agent_b) { create(:account_user, account: sd_account, role: :agent) }
  let(:member_a) { create(:jrc_sd_membership, unit: sd_unit, account_user: agent_a, availability: 'available', capacity: 2) }
  let(:member_b) { create(:jrc_sd_membership, unit: sd_unit, account_user: agent_b, availability: 'available', capacity: 2) }
  let(:team_a) { create(:team, account: sd_account, name: 'Synthetic support A') }
  let(:team_b) { create(:team, account: sd_account, name: 'Synthetic support B') }
  let(:queue_a) { create(:jrc_sd_queue, unit: sd_unit, team: team_a, distribution_mode: 'least_load') }
  let(:queue_b) { create(:jrc_sd_queue, unit: sd_unit, team: team_b, distribution_mode: 'manual') }
  let(:snapshot_conditions) do
    sd_snapshot_attributes.deep_stringify_keys.except('captured_at').merge(
      'policy_conditions' => { 'clock_budgets_seconds' => { 'first_response' => 3600, 'resolution' => 7200 } },
      'calendar_conditions' => { 'format' => JrcServiceDesk::SnapshotCalendar::VERSION,
        'weekly' => (1..7).to_h { |day| [day.to_s, day <= 5 ? [['09:00', '17:00']] : []] },
        'holidays' => ['2026-10-26'], 'exceptions' => {} }
    )
  end

  before do
    travel_to Time.iso8601('2026-10-23T19:00:00Z') # Friday 16:00 Sao Paulo; Monday is a synthetic holiday.
    sd_as_admin!
    member_a
    member_b
    create(:team_member, team: team_a, user: agent_a.user)
    create(:team_member, team: team_b, user: agent_b.user)
    lc_publish(definition: lc_definition(tracked: true))
    publish = JrcServiceDesk::PublishOperationalRulesService.new(user_context: sd_context)
    publish.call(unit_id: sd_unit.id, kind: 'routing', enabled: true, expected_version: 0,
      definition: { 'rules' => [{ 'key' => 'support', 'precedence' => 1, 'match' => {}, 'output' => { 'queue_id' => queue_a.id } }] })
    publish.call(unit_id: sd_unit.id, kind: 'sla_selection', enabled: true, expected_version: 0,
      definition: { 'rules' => [{ 'key' => 'explicit-calendar', 'precedence' => 1, 'match' => {},
        'output' => { 'snapshot' => snapshot_conditions } }] })
  end

  after { travel_back }

  # One HTTP create/read helper is shared by the independent lifecycle scenarios.
  def create_and_reread(key = SecureRandom.uuid)
    post "#{base}/tickets", params: { unit_id: sd_unit.id, ticket: sd_create_attributes }, as: :json,
      headers: headers.merge('Idempotency-Key' => key)
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch('ticket_id')
    get "#{base}/tickets/#{id}", headers: headers
    expect(response).to have_http_status(:ok)
    JrcServiceDesk::Ticket.find(id)
  end

  it 'starts real clocks at creation, with the pinned policy and the selected calendar before any transition' do
    ticket = create_and_reread
    expect(ticket.queue_id).to eq(queue_a.id)
    expect(ticket.assignee_membership_id).to eq(member_a.id)
    cycle = ticket.sla_cycles.sole
    expect(cycle.lifecycle_policy_version_id).to eq(ticket.lifecycle_policy_version_id)
    expect(cycle.started_at).to eq(ticket.opened_at)
    expect(cycle.sla_clocks.find_by!(kind: 'first_response').due_at).to eq(Time.iso8601('2026-10-23T20:00:00Z'))
    expect(cycle.sla_clocks.find_by!(kind: 'resolution').due_at).to eq(Time.iso8601('2026-10-27T13:00:00Z'))
    expect(response.parsed_body.dig('ticket', 'sla', 'clocks').size).to eq(2)
    expect(ticket.lifecycle_transitions.count).to eq(0)
  end

  it 'does not present zero SLA breaches as measurement when no clock cycle exists' do
    ticket = sd_ticket
    get "#{base}/dashboard", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('dashboard', 'total')).to eq(1)
    expect(response.parsed_body.dig('dashboard', 'supervision', 'sla')).to be_nil
    expect(response.parsed_body.fetch('dashboard').fetch('unavailable')).to include('sla_breached')
    expect(ticket.sla_cycles.count).to eq(0)
  end

  it 'routes, reassigns, resolves and closes once while each agent and dashboard reflects persisted ownership' do
    ticket = create_and_reread('integrated-create')
    get "#{base}/tickets", headers: agent_a.user.create_new_auth_token, params: { mine: 'true' }
    expect(response.parsed_body.fetch('items').map { |r| r['id'] }).to eq([ticket.id.to_s])
    get "#{base}/tickets", headers: agent_b.user.create_new_auth_token, params: { mine: 'true' }
    expect(response.parsed_body.dig('meta', 'total')).to eq(0)
    get "#{base}/tickets/#{ticket.id}", headers: agent_b.user.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    get "#{base}/dashboard", headers: headers, params: { per_page: 1 }
    expect(response.parsed_body.fetch('dashboard').slice('total', 'active')).to eq('total' => 1, 'active' => 1)

    post "#{base}/tickets/#{ticket.id}/transfer", headers: headers, as: :json,
      params: { expected_lock_version: ticket.lock_version, assignment: { queue_id: queue_b.id, assignee_account_user_id: agent_b.id } }
    expect(response).to have_http_status(:ok)
    expect(ticket.reload.assignee_membership_id).to eq(member_b.id)
    [agent_a, agent_b].each do |agent|
      get "#{base}/tickets", headers: agent.user.create_new_auth_token, params: { mine: 'true' }
      expect(response.parsed_body.dig('meta', 'total')).to eq(agent == agent_b ? 1 : 0)
    end

    travel 30.minutes
    %w[resolve close].each do |action|
      get "#{base}/tickets/#{ticket.id}/lifecycle", headers: agent_b.user.create_new_auth_token
      read = response.parsed_body
      command = { rule_key: action, solution: 'Synthetic integrated resolution',
        expected_lock_version: read.fetch('lock_version'), expected_policy_version_id: read.dig('policy', 'id') }
      2.times do
        post "#{base}/tickets/#{ticket.id}/lifecycle", headers: agent_b.user.create_new_auth_token.merge('Idempotency-Key' => "integrated-#{action}"),
          params: command, as: :json
        expect(response).to have_http_status(:ok)
      end
    end
    expect(ticket.reload.status.phase).to eq('closed')
    expect(ticket.lifecycle_transitions.order(:id).pluck(:action)).to eq(%w[resolve close])
    expect(ticket.sla_cycles.sole.sla_clocks.find_by!(kind: 'resolution').elapsed_seconds).to eq(1800)
    get "#{base}/dashboard", headers: headers
    expect(response.parsed_body.fetch('dashboard').slice('total', 'active', 'phases')).to eq(
      'total' => 1, 'active' => 0, 'phases' => { 'open' => 0, 'waiting' => 0, 'resolved' => 0, 'closed' => 1, 'cancelled' => 0 })
    expect(ticket.ticket_events.where(event_type: 'ticket_transferred').count).to eq(1)
  end

  it 'keeps a ticket in authorized unassigned triage when no agent is eligible, without assigning the creator' do
    member_a.update!(availability: 'unavailable')
    ticket = create_and_reread
    expect(ticket.assignee_membership_id).to be_nil
    get "#{base}/tickets", headers: headers, params: { assignment: 'unassigned' }
    expect(response.parsed_body.fetch('items').map { |r| r['id'] }).to include(ticket.id.to_s)
    expect(ticket.ticket_events.where(event_type: 'ticket_auto_routed').count).to eq(0)
  end

  it 'counts the full authorized relation rather than one page and isolates another Account and unit' do
    3.times { create_and_reread }
    foreign = create(:jrc_sd_ticket, unit: sd_foreign_unit)
    get "#{base}/tickets", headers: headers, params: { per_page: 1 }
    expect(response.parsed_body.fetch('items').size).to eq(1)
    expect(response.parsed_body.dig('meta', 'total')).to eq(3)
    get "#{base}/dashboard", headers: headers, params: { per_page: 1 }
    expect(response.parsed_body.dig('dashboard', 'total')).to eq(3)
    expect(response.parsed_body.dig('dashboard', 'supervision', 'by_agent').sum { |r| r['count'] }).to eq(3)
    get "#{base}/tickets/#{foreign.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    get "#{base}/dashboard", headers: headers, params: { q: 'no-synthetic-match' }
    expect(response.parsed_body.dig('dashboard', 'total')).to eq(0)
  end

  it 'pauses and resumes resolution using real business seconds across a weekend, holiday and local timezone' do
    ticket = create_and_reread
    travel 30.minutes
    lc_execute(ticket, 'pause', reason_code: 'customer')
    resolution = ticket.sla_cycles.sole.sla_clocks.find_by!(kind: 'resolution')
    deadline = resolution.due_at
    expect(resolution.elapsed_seconds).to eq(1800)
    travel_to Time.iso8601('2026-10-27T12:30:00Z')
    get "#{base}/tickets/#{ticket.id}", headers: headers
    resolution_view = response.parsed_body.dig('ticket', 'sla', 'clocks').find { |row| row['kind'] == 'resolution' }
    expect(resolution_view['deadline_state']).to eq('paused')
    expect(resolution_view['elapsed_seconds']).to eq(1800)
    lc_execute(ticket, 'resume')
    expect(resolution.reload.elapsed_seconds).to eq(1800)
    expect(resolution.due_at).to eq(deadline + 1.hour)
    expect(ticket.lifecycle_pauses.sole.ended_at).to eq(Time.current)
    expect(ticket.sla_cycles.sole.sla_clocks.find_by!(kind: 'first_response').state).to eq('running')
  end

  it 'does not count nonworking time as a breach at a shift boundary and agrees across list, dashboard and reports' do
    ticket = create_and_reread
    travel_to Time.iso8601('2026-10-27T12:00:00Z')
    get "#{base}/dashboard", headers: headers
    expect(response.parsed_body.dig('dashboard', 'supervision', 'sla', 'running_breached')).to eq(0)
    travel 1.minute
    get "#{base}/tickets/#{ticket.id}", headers: headers
    expect(response.parsed_body.dig('ticket', 'sla', 'state')).to eq('overdue')
    get "#{base}/dashboard", headers: headers
    expect(response.parsed_body.dig('dashboard', 'supervision', 'sla', 'running_breached')).to eq(1)
    query = JrcServiceDesk::OperationalReportQuery.new(user_context: sd_context, parameters: { unit_id: sd_unit.id })
    metrics = JrcServiceDesk::OperationalReportMetrics.new(query).call
    expect(metrics.dig(:sla, 'first_response', :running_overdue)).to eq(1)
    expect(metrics.dig(:sla, 'resolution', :running_overdue)).to eq(0)
  end

  it 'records first response only from native delivered reply evidence and preserves it through closure and reopening' do
    ticket = create_and_reread
    conversation = create(:conversation, account: sd_account, contact: sd_contact)
    create(:inbox_member, inbox: conversation.inbox, user: sd_user)
    JrcServiceDesk::LinkConversationService.new(user_context: sd_context).call(ticket_id: ticket.id, conversation_id: conversation.id)
    JrcServiceDesk::AddNoteService.new(user_context: sd_context).call(ticket_id: ticket.id,
      attributes: { body: 'Synthetic internal note', visibility: 'internal' }, idempotency_key: 'internal-not-first-response')
    first = ticket.sla_cycles.sole.sla_clocks.find_by!(kind: 'first_response')
    expect(first.state).to eq('running')
    travel 15.minutes
    message = create(:message, account: sd_account, conversation: conversation, sender: sd_user, message_type: :outgoing,
      private: false, content: 'Synthetic controlled response', status: :delivered, source_id: 'synthetic-accepted-message')
    recorder = JrcServiceDesk::NativeResponseRecorder.new(message, evidence: JrcServiceDesk::NativeResponseRecorder.evidence(message))
    2.times { recorder.call }
    expect(first.reload.state).to eq('completed')
    expect(first.elapsed_seconds).to eq(900)
    expect(ticket.ticket_events.where(event_type: 'first_response_recorded').count).to eq(1)
    travel 15.minutes
    resolved = lc_execute(ticket, 'resolve')
    lc_execute(ticket, 'close')
    prior = resolved.payload.deep_dup
    travel 15.minutes
    lc_execute(ticket, 'reopen')
    expect(ticket.reload.status.phase).to eq('open')
    expect(ticket.sla_cycles.count).to eq(1)
    expect(first.reload.elapsed_seconds).to eq(900)
    expect(first.state).to eq('completed')
    expect(resolved.reload.payload).to eq(prior)
  end

  it 'retains pinned policy and historical deadlines when a new policy version is published' do
    old = create_and_reread
    version_id = old.lifecycle_policy_version_id
    before = old.sla_cycles.sole.sla_clocks.order(:kind).pluck(:due_at)
    definition = lc_definition(tracked: true)
    definition['transitions'].find { |r| r['action'] == 'close' }['requirements']['note'] = true
    lc_publish(definition: definition, expected_version: 1)
    fresh = create_and_reread
    expect(fresh.lifecycle_policy_version_id).not_to eq(version_id)
    expect(old.reload.lifecycle_policy_version_id).to eq(version_id)
    expect(old.sla_cycles.sole.sla_clocks.order(:kind).pluck(:due_at)).to eq(before)
    get "#{base}/tickets/#{old.id}/lifecycle", headers: headers
    expect(response.parsed_body.dig('policy', 'id')).to eq(version_id.to_s)
    expect(response.parsed_body.dig('closure_options', 0, 'steps', 1, 'requirements', 'note')).to be(false)
  end

  it 'keeps missing historical snapshots blocked, permits explicit authorized registration and never mutates on GET' do
    policy = JrcServiceDesk::PublishOperationalRulesService.new(user_context: sd_context)
    current = JrcServiceDesk::OperationalRuleVersion.current(account_id: sd_account.id, unit_id: sd_unit.id, kind: 'sla_selection')
    policy.call(unit_id: sd_unit.id, kind: 'sla_selection', definition: current.definition, enabled: false, expected_version: 1)
    ticket = create_and_reread
    get "#{base}/tickets/#{ticket.id}/lifecycle", headers: headers
    expect(response.parsed_body['unavailable_reason']).to eq('calendar_snapshot_required')
    expect(ticket.sla_cycles.count).to eq(0)
    travel 30.minutes
    JrcServiceDesk::RecordSlaSnapshotService.new(user_context: sd_context).call(ticket_id: ticket.id,
      attributes: snapshot_conditions.merge('captured_at' => ticket.opened_at.iso8601(6)))
    get "#{base}/tickets/#{ticket.id}/lifecycle", headers: headers
    expect(response.parsed_body['unavailable_reason']).to be_nil
    expect(ticket.sla_cycles.count).to eq(0)
    lc_execute(ticket, 'work_status')
    expect(ticket.sla_cycles.sole.started_at).to eq(ticket.opened_at)
    expect(ticket.sla_cycles.sole.sla_clocks.find_by!(kind: 'resolution').elapsed_seconds).to eq(1800)
    expect(ticket.ticket_events.where(event_type: 'sla_snapshot_recorded').count).to eq(1)
  end

  it 'permits supervisor reads only in explicitly granted units without giving configuration permissions' do
    ticket = create_and_reread
    permissions = (JrcServiceDesk::Capabilities::DEFAULTS['agent'] + ['tickets_view_all']).map { |p| "jrc_service_desk_#{p}" }
    role = create(:custom_role, account: sd_account, permissions: permissions)
    supervisor = create(:account_user, account: sd_account, role: :agent, custom_role: role)
    create(:jrc_sd_membership, account_user: supervisor, unit: sd_unit)
    auth = supervisor.user.create_new_auth_token
    get "#{base}/tickets/#{ticket.id}", headers: auth
    expect(response).to have_http_status(:ok)
    get "#{base}/dashboard", headers: auth
    expect(response.parsed_body.dig('dashboard', 'total')).to eq(1)
    get "#{base}/configuration/queues", headers: auth, params: { unit_id: sd_unit.id }
    expect(response).to have_http_status(:forbidden)
    get "#{base}/tickets", headers: auth, params: { unit_id: sd_other_unit.id }
    expect(response).to have_http_status(:not_found)
    sd_account_user.update!(role: :agent)
    sd_membership.update!(active: false)
    post "#{base}/tickets/#{ticket.id}/assign", headers: headers, params: {
      expected_lock_version: ticket.lock_version, assignment: { assignee_account_user_id: agent_b.id } }, as: :json
    expect(response.status).to be_in([403, 404])
    expect(ticket.reload.assignee_membership_id).to eq(member_a.id)
  end

  it 'uses the configured period timezone while daily charts remain explicitly UTC and categories share the same cohort' do
    category = create(:jrc_sd_category, unit: sd_unit)
    sd_ticket(created_at: Time.iso8601('2026-10-23T02:59:59Z'), category: category)
    sd_ticket(created_at: Time.iso8601('2026-10-23T03:00:00Z'), category: category)
    Time.use_zone('America/Sao_Paulo') do
      data = JrcServiceDesk::DashboardService.new(user_context: sd_context).call(
        parameters: { created_from: '2026-10-23', created_to: '2026-10-23', per_page: 1 })
      expect(data[:total]).to eq(1)
      expect(data.dig(:supervision, :timezone)).to eq('UTC')
      expect(data.dig(:supervision, :evolution)).to eq([{ date: '2026-10-23', count: 1 }])
      expect(data.dig(:supervision, :top_categories)).to eq([{ id: category.id.to_s, name: category.name, count: 1 }])
    end
  end

  it 'allows explicitly nonapplicable SLA without inventing a calendar or changing earlier pinned tickets' do
    old = create_and_reread
    current = JrcServiceDesk::OperationalRuleVersion.current(account_id: sd_account.id, unit_id: sd_unit.id, kind: 'sla_selection')
    JrcServiceDesk::PublishOperationalRulesService.new(user_context: sd_context).call(unit_id: sd_unit.id,
      kind: 'sla_selection', definition: current.definition, enabled: false, expected_version: 1)
    lc_publish(definition: lc_definition(tracked: false), expected_version: 1)
    ticket = create_and_reread
    get "#{base}/tickets/#{ticket.id}/lifecycle", headers: headers
    expect(response.parsed_body['unavailable_reason']).to be_nil
    expect(response.parsed_body.fetch('closure_options').size).to eq(1)
    lc_execute(ticket, 'resolve')
    lc_execute(ticket, 'close')
    expect(ticket.sla_cycles.count).to eq(0)
    expect(ticket.sla_snapshots.count).to eq(0)
    expect(old.sla_cycles.count).to eq(1)
    expect(old.reload.lifecycle_policy_version.definition.dig('sla', 'mode')).to eq('calendar_snapshot')
  end

  it 'separates configured note, classification and closing reason requirements from calendar dependency' do
    rules = lc_definition(tracked: true)
    rules['transitions'].select { |r| %w[resolve close].include?(r['action']) }.each do |rule|
      rule['requirements'].merge!('note' => true, 'solution' => true, 'classification' => true)
    end
    rules['transitions'].find { |r| r['action'] == 'close' }['requirements']['fields'] = {
      'closing_reason' => { 'label' => 'Motivo de encerramento', 'type' => 'text', 'required' => true } }
    lc_publish(definition: rules, expected_version: 1)
    ticket = create_and_reread
    get "#{base}/tickets/#{ticket.id}/lifecycle", headers: headers
    expect(response.parsed_body['unavailable_reason']).to be_nil
    command = { rule_key: 'resolve', solution: 'Synthetic solution', expected_lock_version: ticket.lock_version,
      expected_policy_version_id: ticket.lifecycle_policy_version_id }
    post "#{base}/tickets/#{ticket.id}/lifecycle", headers: headers.merge('Idempotency-Key' => 'missing-specific-data'), params: command, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(ticket.lifecycle_transitions.count).to eq(0)
    category = create(:jrc_sd_category, unit: sd_unit)
    JrcServiceDesk::UpdateTicketService.new(user_context: sd_context).call(ticket_id: ticket.id,
      expected_lock_version: ticket.reload.lock_version, attributes: { category_id: category.id })
    lc_execute(ticket, 'resolve', note: 'Synthetic required note', solution: 'Synthetic solution')
    command.merge!(rule_key: 'close', note: 'Synthetic required note', expected_lock_version: ticket.reload.lock_version)
    post "#{base}/tickets/#{ticket.id}/lifecycle", headers: headers.merge('Idempotency-Key' => 'missing-closing-reason'), params: command, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(ticket.reload.status.phase).to eq('resolved')
    command[:fields] = { closing_reason: 'Synthetic approved reason' }
    post "#{base}/tickets/#{ticket.id}/lifecycle", headers: headers.merge('Idempotency-Key' => 'with-closing-reason'), params: command, as: :json
    expect(response).to have_http_status(:ok)
    expect(ticket.reload.status.phase).to eq('closed')
  end

  it 'rejects a forged manual assignee outside the selected native team without changing ownership' do
    ticket = create_and_reread
    expect do
      post "#{base}/tickets/#{ticket.id}/assign", headers: headers, as: :json,
        params: { expected_lock_version: ticket.lock_version, assignment: { assignee_account_user_id: agent_b.id } }
    end.not_to(change { ticket.reload.assignee_membership_id })
    expect(response).to have_http_status(:not_found)
    expect(ticket.ticket_events.where(event_type: 'ticket_assigned').count).to eq(0)
    expect do
      post "#{base}/tickets", headers: headers.merge('Idempotency-Key' => 'forged-team-create'), as: :json,
        params: { unit_id: sd_unit.id, ticket: sd_create_attributes.merge(queue_id: queue_a.id, assignee_account_user_id: agent_b.id) }
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(response).to have_http_status(:not_found)
  end
end
