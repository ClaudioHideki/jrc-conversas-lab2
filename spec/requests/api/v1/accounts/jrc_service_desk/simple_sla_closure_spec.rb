# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Explicit simple closure and automatic SLA', type: :request do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  include ActiveSupport::Testing::TimeHelpers

  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:definition) do
    rules = lc_definition(tracked: true)
    rules['sla'].merge!('obligation' => 'operational', 'missing_configuration' => 'allow_operational_closure')
    rules['transitions'].select { |r| %w[resolve close].include?(r['action']) }.each do |rule|
      rule['requirements']['fields']['closing_reason'] = { 'label' => 'Motivo do encerramento', 'type' => 'text', 'required' => true }
    end
    rules
  end
  let(:snapshot) do
    sd_snapshot_attributes.deep_stringify_keys.except('captured_at').merge(
      'policy_conditions' => { 'clock_budgets_seconds' => { 'first_response' => 3600, 'resolution' => 7200 } },
      'calendar_conditions' => { 'format' => JrcServiceDesk::SnapshotCalendar::VERSION,
        'weekly' => (1..7).to_h { |d| [d.to_s, d <= 5 ? [['09:00', '17:00']] : []] }, 'holidays' => [], 'exceptions' => {} })
  end

  before do
    travel_to Time.iso8601('2026-10-23T12:00:00Z')
    sd_as_admin!
    lc_publish(definition: definition)
  end
  after { travel_back }

  # Repeated authenticated commands retain each stage's own version and request key.
  def transition(ticket, action, reason: 'Atendimento concluído', key: SecureRandom.uuid)
    get "#{base}/tickets/#{ticket.id}/lifecycle", headers: headers
    policy_id = response.parsed_body.fetch('policy').fetch('id')
    post "#{base}/tickets/#{ticket.id}/lifecycle", headers: headers.merge('Idempotency-Key' => key), as: :json,
      params: { rule_key: action, expected_lock_version: ticket.reload.lock_version, expected_policy_version_id: policy_id,
        closing_reason: reason, fields: { closing_reason: reason } }
  end

  it 'closes with one real reason, audits both commands and keeps missing SLA unavailable without fabricating clocks' do
    ticket = sd_ticket
    original = ticket.attributes.slice('title', 'description', 'category_id', 'service_fields')
    get "#{base}/tickets/#{ticket.id}/lifecycle", headers: headers
    expect(response.parsed_body['closure_options'].sole['steps'].map { |r| r['action'] }).to eq(%w[resolve close])
    expect(response.parsed_body.dig('measurement', 'pending_reason')).to eq('targets_and_calendar_missing')
    travel 12.minutes
    transition(ticket, 'resolve')
    expect(response).to have_http_status(:ok)
    travel 3.minutes
    transition(ticket, 'close')
    expect(response).to have_http_status(:ok)
    expect(ticket.reload.status.phase).to eq('closed')
    expect(ticket.attributes.slice(*original.keys)).to eq(original)
    expect(ticket.sla_cycles.count).to eq(0)
    events = ticket.lifecycle_transitions.order(:id)
    expect(events.map(&:action)).to eq(%w[resolve close])
    expect(events.map { |r| r.payload['closing_reason'] }).to eq(['Atendimento concluído'] * 2)
    expect(events.all? { |r| r.payload.dig('sla', 'calculation_pending') }).to be(true)
    expect(events.none? { |r| r.payload.key?('solution') || r.payload.key?('note') }).to be(true)
    get "#{base}/tickets/#{ticket.id}/lifecycle", headers: headers
    measured = response.parsed_body.fetch('measurement')
    expect(measured['result']).to eq('unavailable')
    expect(measured['first_response']).to be_nil
    expect(measured.dig('resolution', 'elapsed_seconds')).to eq(720)
    expect(measured.dig('closure', 'elapsed_seconds')).to eq(900)
    get "#{base}/dashboard", headers: headers
    expect(response.parsed_body.dig('dashboard', 'total')).to eq(1)
    expect(response.parsed_body.dig('dashboard', 'phases', 'closed')).to eq(1)
    expect(response.parsed_body.dig('dashboard', 'supervision', 'sla')).to be_nil
    expect(response.parsed_body.dig('dashboard', 'supervision', 'sla_coverage', 'tickets_with_pending_result')).to eq(1)
    get "#{base}/tickets/#{ticket.id}/timeline", headers: headers, params: { view: 'history' }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Atendimento concluído')
  end

  it 'rejects a blank reason without changing state, history or policy binding' do
    ticket = sd_ticket
    transition(ticket, 'resolve', reason: ' ')
    expect(response).to have_http_status(:unprocessable_entity)
    expect(ticket.reload.status).to eq(sd_status)
    expect(ticket.lifecycle_transitions.count).to eq(0)
    expect(ticket.lifecycle_policy_version_id).to be_nil
  end

  it 'keeps contractual configuration and mandatory approval blocking independently' do
    contract = JrcServiceDesk::Service.create!(account: sd_account, unit: sd_unit, name: 'Synthetic contractual service', code: 'contractual', active: true)
    strict = definition.deep_dup
    strict['sla'].merge!('obligation' => 'contractual', 'missing_configuration' => 'block')
    lc_publish(definition: strict, service: contract)
    ticket = sd_ticket(service: contract)
    transition(ticket, 'resolve')
    expect(response).to have_http_status(:unprocessable_entity)
    expect(ticket.reload.status.phase).to eq('open')
    approved_service = JrcServiceDesk::Service.create!(account: sd_account, unit: sd_unit, name: 'Synthetic approved service', code: 'approved', active: true, approval_required: true)
    ticket = sd_ticket(service: approved_service)
    transition(ticket, 'resolve')
    expect(response).to have_http_status(:unprocessable_entity)
    expect(ticket.lifecycle_transitions.count).to eq(0)
  end

  it 'refuses to publish a contractual waiver and leaves old pinned policies strict' do
    invalid = definition.deep_dup
    invalid['sla']['obligation'] = 'contractual'
    expect { lc_publish(definition: invalid, expected_version: 1) }.to raise_error(ArgumentError)
    strict = lc_definition(tracked: true)
    old = lc_publish(definition: strict, expected_version: 1).current_version
    ticket = sd_ticket(lifecycle_policy_version: old)
    lc_publish(definition: definition, expected_version: 2)
    transition(ticket, 'resolve')
    expect(response).to have_http_status(:unprocessable_entity)
    expect(ticket.reload.lifecycle_policy_version_id).to eq(old.id)
    expect(ticket.status.phase).to eq('open')
  end

  it 'records a verified public first response without targets and ignores internal notes, assignment and duplicate evidence' do
    ticket = sd_ticket
    conversation = create(:conversation, account: sd_account, contact: sd_contact)
    create(:inbox_member, inbox: conversation.inbox, user: sd_user)
    JrcServiceDesk::LinkConversationService.new(user_context: sd_context).call(ticket_id: ticket.id, conversation_id: conversation.id)
    travel 12.minutes
    private_message = create(:message, account: sd_account, conversation: conversation, sender: sd_user,
      message_type: :outgoing, private: true, content: 'Synthetic internal note', status: :delivered, source_id: 'synthetic-private')
    JrcServiceDesk::NativeResponseRecorder.new(private_message, evidence: JrcServiceDesk::NativeResponseRecorder.evidence(private_message)).call
    expect(ticket.ticket_events.where(event_type: 'first_response_observed').count).to eq(0)
    message = create(:message, account: sd_account, conversation: conversation, sender: sd_user,
      message_type: :outgoing, private: false, content: 'Synthetic public answer', status: :delivered, source_id: 'synthetic-public')
    2.times { JrcServiceDesk::NativeResponseRecorder.new(message, evidence: JrcServiceDesk::NativeResponseRecorder.evidence(message)).call }
    expect(ticket.ticket_events.where(event_type: 'first_response_observed').count).to eq(1)
    expect(ticket.sla_cycles.count).to eq(0)
    get "#{base}/tickets/#{ticket.id}/lifecycle", headers: headers
    expect(response.parsed_body.dig('measurement', 'first_response', 'elapsed_seconds')).to eq(720)
    expect(response.parsed_body.dig('measurement', 'result')).to eq('unavailable')
  end

  it 'publishes targets through real authorized HTTP, rereads their versions and denies an ordinary agent' do
    body = { unit_id: sd_unit.id, kind: 'sla_selection', enabled: true, expected_version: 0,
      definition: { rules: [{ key: 'synthetic-targets', precedence: 1, match: {}, output: { snapshot: snapshot } }] } }
    post "#{base}/operational_rules", headers: headers, params: body, as: :json
    expect(response).to have_http_status(:created)
    get "#{base}/operational_rules", headers: headers, params: { unit_id: sd_unit.id, kind: 'sla_selection' }
    expect(response.parsed_body.dig('versions', 0, 'definition', 'rules', 0, 'output', 'snapshot', 'policy_conditions', 'clock_budgets_seconds', 'resolution')).to eq(7200)
    first = JrcServiceDesk::OperationalRuleVersion.last
    expect(first.published_by_membership_id).to eq(sd_membership.id)
    sd_account_user.update!(role: :agent)
    body[:expected_version] = 1
    body[:definition][:rules][0][:output][:snapshot]['policy_conditions']['clock_budgets_seconds']['resolution'] = 999999
    post "#{base}/operational_rules", headers: headers, params: body, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(JrcServiceDesk::OperationalRuleVersion.count).to eq(1)
    expect(first.reload.version).to eq(1)
  end

  it 'rejects zero targets, wrong clock sets and invalid calendars rather than activating defaults' do
    [0, '60', -1].each do |value|
      invalid = snapshot.deep_dup
      invalid['policy_conditions']['clock_budgets_seconds']['first_response'] = value
      expect { JrcServiceDesk::PublishOperationalRulesService.new(user_context: sd_context).call(unit_id: sd_unit.id,
        kind: 'sla_selection', enabled: true, expected_version: 0,
        definition: { 'rules' => [{ 'key' => 'invalid', 'precedence' => 1, 'match' => {}, 'output' => { 'snapshot' => invalid } }] }) }.to raise_error(ArgumentError)
    end
    invalid = snapshot.deep_dup
    invalid['policy_conditions']['clock_budgets_seconds'] = { 'first_response' => 3600 }
    expect { JrcServiceDesk::PublishOperationalRulesService.new(user_context: sd_context).call(unit_id: sd_unit.id,
      kind: 'sla_selection', enabled: true, expected_version: 0,
      definition: { 'rules' => [{ 'key' => 'invalid', 'precedence' => 1, 'match' => {}, 'output' => { 'snapshot' => invalid } }] }) }.to raise_error(ArgumentError)
    invalid = snapshot.deep_dup
    invalid['calendar_conditions']['weekly']['1'] = [['17:00', '09:00']]
    expect { JrcServiceDesk::PublishOperationalRulesService.new(user_context: sd_context).call(unit_id: sd_unit.id,
      kind: 'sla_selection', enabled: true, expected_version: 0,
      definition: { 'rules' => [{ 'key' => 'invalid', 'precedence' => 1, 'match' => {}, 'output' => { 'snapshot' => invalid } }] }) }.to raise_error(ArgumentError)
    expect(JrcServiceDesk::OperationalRuleVersion.count).to eq(0)
  end

  it 'versions edited targets for new intake and retains the old ticket snapshot, clocks and deadlines' do
    publish = JrcServiceDesk::PublishOperationalRulesService.new(user_context: sd_context)
    rules = { 'rules' => [{ 'key' => 'targets', 'precedence' => 1, 'match' => {}, 'output' => { 'snapshot' => snapshot } }] }
    first = publish.call(unit_id: sd_unit.id, kind: 'sla_selection', enabled: true, expected_version: 0, definition: rules)
    old = JrcServiceDesk::CreateTicketService.new(user_context: sd_context).call(unit_id: sd_unit.id,
      attributes: sd_create_attributes, idempotency_key: 'first-target-version')
    old_snapshot = old.latest_sla_snapshot.attributes.deep_dup
    old_clocks = old.sla_cycles.sole.sla_clocks.order(:kind).pluck(:budget_seconds, :due_at)
    rules = rules.deep_dup
    rules['rules'][0]['output']['snapshot']['policy_version'] = 'synthetic-v2'
    rules['rules'][0]['output']['snapshot']['policy_conditions']['clock_budgets_seconds']['resolution'] = 10800
    second = publish.call(unit_id: sd_unit.id, kind: 'sla_selection', enabled: true, expected_version: 1, definition: rules)
    fresh = JrcServiceDesk::CreateTicketService.new(user_context: sd_context).call(unit_id: sd_unit.id,
      attributes: sd_create_attributes, idempotency_key: 'second-target-version')
    expect(second.version).to eq(2)
    expect(second.published_by_membership_id).to eq(sd_membership.id)
    expect(first.reload.definition['rules'][0]['output']['snapshot']['policy_conditions']['clock_budgets_seconds']['resolution']).to eq(7200)
    expect(fresh.sla_cycles.sole.sla_clocks.find_by!(kind: 'resolution').budget_seconds).to eq(10800)
    expect(old.reload.latest_sla_snapshot.attributes).to eq(old_snapshot)
    expect(old.sla_cycles.sole.sla_clocks.order(:kind).pluck(:budget_seconds, :due_at)).to eq(old_clocks)
  end

  it 'registers authorized missing conditions explicitly without fabricating a historical result or rewriting the earlier resolution' do
    ticket = sd_ticket
    transition(ticket, 'resolve')
    expect(response).to have_http_status(:ok)
    original = ticket.lifecycle_transitions.sole.payload.deep_dup
    travel 30.minutes
    lc_snapshot(ticket)
    expect(ticket.ticket_events.where(event_type: 'sla_snapshot_recorded').count).to eq(1)
    get "#{base}/tickets/#{ticket.id}/lifecycle", headers: headers
    expect(ticket.sla_cycles.count).to eq(0)
    transition(ticket, 'close')
    expect(response).to have_http_status(:ok)
    expect(ticket.sla_cycles.count).to eq(0)
    expect(ticket.lifecycle_transitions.order(:id).first.payload).to eq(original)
    expect(ticket.lifecycle_transitions.order(:id).last.payload.dig('sla', 'pending_reason')).to eq('result_unavailable')
  end

  it 'measures verified first responses inside and outside configured targets and excludes absent responses from compliance' do
    JrcServiceDesk::PublishOperationalRulesService.new(user_context: sd_context).call(unit_id: sd_unit.id, kind: 'sla_selection',
      enabled: true, expected_version: 0, definition: { 'rules' => [{ 'key' => 'explicit', 'precedence' => 1, 'match' => {}, 'output' => { 'snapshot' => snapshot } }] })
    tickets = 2.times.map do |index|
      JrcServiceDesk::CreateTicketService.new(user_context: sd_context).call(unit_id: sd_unit.id,
        attributes: sd_create_attributes, idempotency_key: "response-target-#{index}")
    end
    tickets.each_with_index do |ticket, index|
      conversation = create(:conversation, account: sd_account, contact: sd_contact)
      create(:inbox_member, inbox: conversation.inbox, user: sd_user)
      JrcServiceDesk::LinkConversationService.new(user_context: sd_context).call(ticket_id: ticket.id, conversation_id: conversation.id)
      travel_to ticket.opened_at + (index.zero? ? 900 : 3601)
      message = create(:message, account: sd_account, conversation: conversation, sender: sd_user,
        message_type: :outgoing, private: false, content: 'Synthetic verified reply', status: :delivered, source_id: "verified-#{index}")
      JrcServiceDesk::NativeResponseRecorder.new(message, evidence: JrcServiceDesk::NativeResponseRecorder.evidence(message)).call
      expect(ticket.sla_cycles.sole.sla_clocks.find_by!(kind: 'first_response').met?).to eq(index.zero?)
      transition(ticket, 'resolve')
      expect(response).to have_http_status(:ok)
      transition(ticket, 'close')
      expect(response).to have_http_status(:ok)
    end
    get "#{base}/dashboard", headers: headers
    coverage = response.parsed_body.dig('dashboard', 'supervision', 'sla_coverage')
    expect(coverage.slice('completed_clocks', 'met_clocks', 'breached_clocks')).to eq('completed_clocks' => 4, 'met_clocks' => 3, 'breached_clocks' => 1)
  end

  it 'distinguishes missing budgets from missing calendar and does not manufacture SLA result data' do
    empty_targets = JrcServiceDesk::SlaSnapshot.new(policy_conditions: {}, calendar_conditions: snapshot['calendar_conditions'], timezone: snapshot['timezone'])
    bad_calendar = JrcServiceDesk::SlaSnapshot.new(policy_conditions: snapshot['policy_conditions'], calendar_conditions: {}, timezone: snapshot['timezone'])
    expect(JrcServiceDesk::SlaConfigurationState.reason(empty_targets, %w[first_response resolution])).to eq('targets_missing')
    expect(JrcServiceDesk::SlaConfigurationState.reason(bad_calendar, %w[first_response resolution])).to eq('calendar_missing')
    expect(JrcServiceDesk::SlaConfigurationState.reason(nil, %w[first_response resolution])).to eq('targets_and_calendar_missing')
  end

  it 'denies SLA publication into another Account without adding any version' do
    post "#{base}/operational_rules", headers: headers, as: :json,
      params: { unit_id: sd_foreign_unit.id, kind: 'sla_selection', enabled: true, expected_version: 0,
        definition: { rules: [{ key: 'foreign', precedence: 1, match: {}, output: { snapshot: snapshot } }] } }
    expect(response).to have_http_status(:not_found)
    expect(JrcServiceDesk::OperationalRuleVersion.count).to eq(0)
  end

  it 'redacts the audited closing reason from an HTTP history reader without protected note permission' do
    ticket = sd_ticket
    transition(ticket, 'resolve', reason: 'Motivo interno protegido')
    expect(response).to have_http_status(:ok)
    permissions = (JrcServiceDesk::Capabilities::DEFAULTS['agent'].reject { |key| key == 'notes_view' } + ['tickets_view_all']).map { |key| "jrc_service_desk_#{key}" }
    role = create(:custom_role, account: sd_account, permissions: permissions)
    member = create(:account_user, account: sd_account, role: :agent, custom_role: role)
    create(:jrc_sd_membership, unit: sd_unit, account_user: member)
    get "#{base}/tickets/#{ticket.id}/timeline", headers: member.user.create_new_auth_token, params: { view: 'history' }
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('Motivo interno protegido')
    expect(ticket.ticket_events.find_by!(event_type: 'lifecycle_transitioned').data['closing_reason']).to eq('Motivo interno protegido')
  end

  it 'preserves an overdue resolution after closing and never completes first response from closing alone' do
    ticket = sd_ticket
    lc_snapshot(ticket)
    lc_execute(ticket, 'work_status')
    travel 9.hours
    transition(ticket, 'resolve')
    expect(response).to have_http_status(:ok)
    travel 1.hour
    transition(ticket, 'close')
    expect(response).to have_http_status(:ok)
    clock = ticket.sla_cycles.sole.sla_clocks.find_by!(kind: 'resolution')
    expect(clock.met?).to be(false)
    expect(clock.achieved_at).to be < Time.current
    expect(ticket.sla_cycles.sole.sla_clocks.find_by!(kind: 'first_response').met?).to be_nil
  end
end
