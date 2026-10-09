require 'rails_helper'

# Real Capture/worker sources, authenticated HTTP approval, native persistence and GET.
# R02/R07 Project Task creation has additional complete-chain coverage in
# jrc_nico_helpdesk_project_tasks_spec; this matrix also exercises their native Project/TicketTask tools.
RSpec.describe 'NICO HelpDesk R01-R16 native approval chains', type: :request do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures

  let(:selected_rule) { 'R01' }
  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'Synthetic whole-chain customer') }
  let(:ticket) { sd_ticket(company_id: company.id, opened_at: selected_rule == 'R13' ? 16.days.ago : Time.current) }
  let(:pilot_companies) { [company.id] }
  let(:higher_priority) { create(:jrc_sd_priority, unit: sd_unit, position: 2, name: 'Reviewed higher priority') }
  let(:headers) { sd_user.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_nico/helpdesk" }
  let(:desk_base) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:definition) do
    value = JrcNico::Helpdesk::Definition.defaults.merge(
      'unit_ids' => [sd_unit.id], 'company_ids' => pilot_companies, 'operator_ids' => [sd_account_user.id]
    )
    rule = value.fetch('rules').fetch(selected_rule)
    rule['enabled'] = true
    rule['confirmed'] = true if rule.key?('confirmed')
    if %w[R01 R11 R12].include?(selected_rule)
      value['priority_order'] = { sd_unit.id.to_s => [sd_priority.id, higher_priority.id] }
    end
    if selected_rule == 'R12'
      rule['critical_company_ids'] = [company.id]
      rule['priority_ids'] = { sd_unit.id.to_s => higher_priority.id }
    end
    value
  end
  let(:policy) do
    JrcNico::Helpdesk::PolicyVersion.create!(
      account: sd_account, author: sd_account_user, number: 1, state: 'published', enabled: true,
      published_at: Time.current, definition: definition, digest: JrcNico::Helpdesk::Definition.digest(definition)
    )
  end

  before do
    travel_to Time.iso8601('2026-10-08T12:00:00Z')
    sd_account.update!(custom_attributes: { 'nico_enabled' => true })
    sd_account.enable_features!('jrc_customer_master', 'jrc_projects')
    sd_account_user.update!(jrc_projects_enabled: true)
    sd_as_admin!
  end

  def attach_profile(row)
    JrcNico::Helpdesk::TicketProfile.create!(
      account: sd_account, unit: sd_unit, ticket: row, company_id: row.company_id,
      case_kind: 'defect', defect_key: 'voice.trunk'
    )
  end

  def occurrence_sources
    count = { 'R01' => 2, 'R02' => 3, 'R03' => 5, 'R04' => 4 }.fetch(selected_rule, 1)
    (count - 1).times do |index|
      customer = if selected_rule == 'R04'
                   JrcCustomers::Company.create!(account: sd_account, name: "Synthetic affected customer #{index}")
                 else
                   company
                 end
      pilot_companies << customer.id unless pilot_companies.include?(customer.id)
      attach_profile(sd_ticket(company_id: customer.id))
    end
  end

  def clock_source
    return unless %w[R05 R06 R07 R08 R09].include?(selected_rule)

    lc_publish(definition: lc_definition(tracked: true))
    lc_snapshot(ticket)
    lc_execute(ticket, 'work_status')
    clock = ticket.reload.sla_cycles.last.sla_clocks.find_by!(kind: 'resolution')
    target = if selected_rule == 'R05'
               clock.anchor_at + (clock.budget_seconds * 0.8).seconds
             else
               clock.due_at + { 'R06' => 1, 'R07' => 24.hours + 1, 'R08' => 72.hours + 1, 'R09' => 7.days + 1 }.fetch(selected_rule)
             end
    travel_to(target, with_usec: true)
  end

  def customer_text_source
    return unless %w[R10 R11].include?(selected_rule)

    text = selected_rule == 'R10' ? 'Novamente o mesmo problema; reclamação explícita.' : 'Notificação extrajudicial do advogado.'
    note = JrcServiceDesk::AddNoteService.new(user_context: sd_context).call(
      ticket_id: ticket.id, attributes: { body: text }, idempotency_key: SecureRandom.uuid
    )
    JrcNico::Helpdesk::ProfileWriter.new(sd_account_user).call(ticket_id: ticket.id, attributes: { customer_note_ids: [note.id] })
  end

  def closure_source
    return unless %w[R14 R15].include?(selected_rule)

    configure_shared_survey if selected_rule == 'R15'
    lc_publish
    lc_execute(ticket, 'resolve')
    lc_execute(ticket, 'close')
    return unless selected_rule == 'R14'

    JrcNico::Helpdesk::ProfileWriter.new(sd_account_user).call(ticket_id: ticket.id, attributes: { negative_return: true })
  end

  def capture_source
    attach_profile(ticket)
    occurrence_sources
    clock_source
    customer_text_source
    closure_source
    policy
    capture = JrcNico::Helpdesk::Capture.new(sd_account_user)
    trigger = { 'R14' => 'customer_return', 'R15' => 'closed', 'R16' => 'created' }.fetch(selected_rule, 'monitor')
    values = capture.call(ticket: ticket.reload, trigger: trigger, origin_key: "whole-chain:#{ticket.id}")
    expect(values.map(&:rule_key)).to eq([selected_rule])
    event = values.fetch(0)
    expect(event).to have_attributes(actor_id: sd_account_user.id, policy_version_id: policy.id, account_id: sd_account.id)
    expect(event.evidence).to include('cycle_key' => JrcNico::Helpdesk::CycleEvidence.key(ticket.reload))
    expect do
      retry_values = capture.call(ticket: ticket, trigger: trigger, origin_key: "whole-chain-retry:#{ticket.id}")
      expect(retry_values.map(&:id)).to eq([event.id])
    end.not_to change(JrcNico::Helpdesk::Event, :count)
    event
  end

  def process_source(event)
    effects = operational_counts
    JrcNico::Helpdesk::EventJob.perform_now(event.id)
    expect(event.reload).to have_attributes(state: 'prepared', reason: 'approval_required')
    expect(event.result).to include('automatic_mutation' => false, 'tools' => JrcNico::Helpdesk::ActionPreview::RULE_TOOLS.fetch(selected_rule))
    expect(operational_counts).to eq(effects)
    get "#{base}/events", headers: headers
    expect(response).to have_http_status(:ok)
    row = response.parsed_body.fetch('events').find { |value| value.fetch('id') == event.id }
    expect(row).to include('rule_key' => selected_rule, 'state' => 'prepared', 'evidence' => event.evidence)
  end

  def native_action(event)
    return ['update_service_ticket', event.result.fetch('priority_arguments')] if %w[R01 R11 R12].include?(selected_rule)
    return ['create_project', { 'ticket_id' => ticket.id, 'name' => 'Reviewed root-cause project' }] if selected_rule == 'R02'

    if selected_rule == 'R04'
      return ['create_service_incident', { 'unit_id' => sd_unit.id, 'title' => 'Reviewed mass incident',
                                           'severity' => 'high', 'ticket_ids' => event.evidence.fetch('ticket_ids') }]
    end
    if selected_rule == 'R07'
      return ['create_service_ticket_task', { 'ticket_id' => ticket.id, 'title' => 'Review overdue resolution evidence',
                                              'priority' => 'high', 'checklist' => [{ 'title' => 'Review authorized evidence', 'done' => false }] }]
    end
    if selected_rule == 'R14'
      return ['transition_service_ticket', { 'ticket_id' => ticket.id, 'rule_key' => 'reopen',
                                             'expected_lock_version' => ticket.reload.lock_version, 'expected_policy_version_id' => ticket.lifecycle_policy_version_id }]
    end
    ['add_service_ticket_note', { 'ticket_id' => ticket.id, 'body' => "Reviewed internal evidence for #{selected_rule}; no customer dispatch." }]
  end

  def prepare_action(event, tool, arguments)
    effects = operational_counts
    post "#{base}/approvals", params: { event_id: event.id, tool: tool, arguments: arguments }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    approval = JrcNico::Helpdesk::Approval.find(response.parsed_body.fetch('id'))
    expect(approval).to have_attributes(state: 'pending', approver_id: sd_account_user.id, event_id: event.id)
    expect(approval.command).to have_attributes(tool: tool, status: 'awaiting_confirmation', arguments: arguments)
    expect(operational_counts).to eq(effects)
    approval
  end

  def execute_action(approval)
    messages = Message.count
    post "#{base}/approvals/#{approval.id}/approve", params: { payload_digest: approval.payload_digest }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('id' => approval.id, 'state' => 'succeeded')
    command = approval.command.reload
    expect(command).to have_attributes(status: 'succeeded', tool: approval.command.tool)
    expect(command.result).not_to have_key('browser_action')
    expect(Message.count).to eq(messages)
    command
  end

  def verify_native_effect(command)
    type = command.result.fetch('resource_type')
    record = type.constantize.find(command.result.fetch('record').fetch('id'))
    expect(record.account_id).to eq(sd_account.id)
    case type
    when 'JrcServiceDesk::Ticket' then verify_ticket_effect(record)
    when 'JrcServiceDesk::Incident' then verify_incident_effect(record)
    when 'JrcServiceDesk::TicketTask' then verify_task_effect(record)
    when 'JrcProjects::Project' then verify_project_effect(record)
    when 'JrcServiceDesk::TicketNote' then verify_note_effect(record, command)
    else raise "Unproven native effect #{type}"
    end
    record
  end

  def verify_ticket_effect(record)
    expect(record.id).to eq(ticket.id)
    if selected_rule == 'R14'
      transition = record.lifecycle_transitions.find_by!(action: 'reopen')
      expect(transition).to have_attributes(actor_membership_id: sd_membership.id, unit_id: sd_unit.id)
      expect(transition.payload.dig('origin', 'kind')).to eq('operator_assisted_nico')
      expect(record.status.phase).to eq('open')
    else
      expect(record.priority_id).to eq(higher_priority.id)
      event = record.ticket_events.find_by!(event_type: 'ticket_updated')
      expect(event.data.dig('origin', 'kind')).to eq('operator_assisted_nico')
    end
    get "#{desk_base}/tickets/#{record.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('ticket')).to include('id' => record.id.to_s, 'unit_id' => sd_unit.id.to_s)
  end

  def verify_incident_effect(record)
    expect(record).to have_attributes(unit_id: sd_unit.id, title: 'Reviewed mass incident', severity: 'high',
                                      created_by_membership_id: sd_membership.id)
    command_ticket_ids = JrcNico::Helpdesk::Event.find_by!(ticket: ticket, rule_key: 'R04').evidence.fetch('ticket_ids').sort
    expect(record.tickets.pluck(:id).sort).to eq(command_ticket_ids)
    expect(JrcServiceDesk::Ticket.where(id: command_ticket_ids).pluck(:incident_id).uniq).to eq([record.id])
    get "#{desk_base}/incidents/#{record.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('incident')).to include('id' => record.id.to_s, 'ticket_ids' => command_ticket_ids.map(&:to_s))
  end

  def verify_task_effect(record)
    expect(record).to have_attributes(ticket_id: ticket.id, unit_id: sd_unit.id, priority: 'high', visibility: 'internal',
                                      created_by_membership_id: sd_membership.id)
    expect(record.checklist).to eq([{ 'title' => 'Review authorized evidence', 'done' => false }])
    get "#{desk_base}/tickets/#{ticket.id}/cockpit", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(record.title)
  end

  def verify_project_effect(record)
    expect(record).to have_attributes(name: 'Reviewed root-cause project', created_by_id: sd_user.id)
    expect(record.operation_links.find_by!(ticket_id: ticket.id)).to have_attributes(account_id: sd_account.id, ticket_unit_id: sd_unit.id)
    get "/api/v1/accounts/#{sd_account.id}/projects/projects/#{record.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('data')).to include('id' => record.id, 'name' => record.name)
  end

  def verify_note_effect(record, command)
    expect(record).to have_attributes(ticket_id: ticket.id, unit_id: sd_unit.id, visibility: 'internal',
                                      author_membership_id: sd_membership.id, body: command.arguments.fetch('body'))
    expect(record.notification_channels).to eq([])
    expect(record.idempotency_key).to eq("nico_#{command.id}_#{command.request_id}")
    get "#{desk_base}/tickets/#{ticket.id}/notes/#{record.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item')).to include('id' => record.id.to_s, 'body' => record.body)
  end

  def replay_and_revoke(approval, record)
    counts = operational_counts.merge('commands' => JrcNico::Command.count, 'approvals' => JrcNico::Helpdesk::Approval.count)
    post "#{base}/approvals/#{approval.id}/approve", params: { payload_digest: approval.payload_digest }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('state')).to eq('succeeded')
    expect(operational_counts.merge('commands' => JrcNico::Command.count, 'approvals' => JrcNico::Helpdesk::Approval.count)).to eq(counts)
    get "#{base}/approvals", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('approvals').pluck('id')).to include(approval.id)
    sd_membership.update!(active: false)
    %w[events approvals].each do |kind|
      get "#{base}/#{kind}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch(kind)).to be_empty
    end
    expect(record.reload).to be_persisted
  end

  def operational_counts
    [JrcServiceDesk::TicketNote, JrcServiceDesk::TicketTask, JrcServiceDesk::Incident,
     JrcServiceDesk::LifecycleTransition, JrcProjects::Project, JrcProjects::Task, Message]
      .index_with(&:count).transform_keys(&:name)
  end

  (JrcNico::Helpdesk::Definition::RULE_KEYS - ['R15']).each do |key|
    context "with native rule #{key}" do
      let(:selected_rule) { key }

      it 'captures, proposes, approves and reloads the permitted native effect once and hides it after Unit revocation' do
        event = capture_source
        process_source(event)
        tool, arguments = native_action(event)
        approval = prepare_action(event, tool, arguments)
        command = execute_action(approval)
        record = verify_native_effect(command)
        replay_and_revoke(approval, record)
      end
    end
  end

  it 'blocks the real worker after the original Unit grant is revoked without creating a proposal or mutation' do
    event = capture_source
    effects = operational_counts
    sd_membership.update!(active: false)
    JrcNico::Helpdesk::EventJob.perform_now(event.id)
    expect(event.reload).to have_attributes(state: 'blocked', reason: 'permission_revoked')
    expect(event.result).to eq({})
    expect(operational_counts).to eq(effects)
    expect(JrcNico::Helpdesk::Approval.where(event: event)).to be_empty
  end

  it 'rejects an unreviewed digest and a subsequently disabled policy without native writes' do
    event = capture_source
    process_source(event)
    tool, arguments = native_action(event)
    approval = prepare_action(event, tool, arguments)
    effects = operational_counts
    post "#{base}/approvals/#{approval.id}/approve", params: { payload_digest: '0' * 64 }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(approval.reload.state).to eq('pending')
    post "#{base}/policies/#{policy.id}/disable",
         params: { reason: 'Explicit reviewed local policy halt', request_key: SecureRandom.uuid }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(policy.reload.enabled?).to be(false)
    expect(policy.enabled).to be(true)
    post "#{base}/approvals/#{approval.id}/approve", params: { payload_digest: approval.payload_digest }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq('error' => 'You are not authorized to do this action')
    expect(approval.reload.state).to eq('pending')
    expect(operational_counts).to eq(effects)
    get "#{base}/events", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('events').pluck('id')).to include(event.id)
  end

  def configure_shared_survey
    sd_account.enable_features!('jrc_relationship', 'jrc_crm')
    sd_contact.update!(company_id: company.id, custom_attributes: { 'survey_consent' => true })
    JrcRelationship::Assignment.create!(account: sd_account, company: company, owner: sd_user, status: 'active')
    JrcRelationship::Configuration.create!(account: sd_account, rules: { survey_automation_enabled: true })
    survey_definition = JrcRelationship::SurveyDefinition.create!(
      account: sd_account, name: 'Explicit whole-chain NPS', code: 'whole_chain_nps', kind: 'nps', status: 'active',
      questions: [{ 'key' => 'rating', 'text' => 'How likely are you to recommend us?', 'type' => 'scale',
                    'min' => 0, 'max' => 10, 'required' => true }], settings: { 'recovery_enabled' => false }
    )
    JrcRelationship::SurveyRule.create!(
      account: sd_account, name: 'Explicit native Service Desk closure', definition: survey_definition,
      execution_member: sd_account_user, active: true, matchers: { 'source_type' => 'JrcServiceDesk::Ticket' },
      settings: { 'channel' => 'public_link' }
    )
  end

  context 'with R15 using the shared native SurveyEngine' do
    let(:selected_rule) { 'R15' }

    def verify_shared_survey_readback(decision)
      get "/api/v1/accounts/#{sd_account.id}/relationship/survey_decisions",
          params: { source_type: ticket.class.name, source_id: ticket.id }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('payload').pluck('id')).to eq([decision.id])
      get "/api/v1/accounts/#{sd_account.id}/relationship/records/surveys", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('payload').pluck('id')).to include(decision.survey_id)
    end

    it 'reads the exact native closure decision and survey without scheduling or sending a second survey' do
      event = capture_source
      decision = JrcRelationship::SurveyDispatchDecision.find(event.evidence.fetch('survey_decision_id'))
      expect(decision).to have_attributes(source_type: ticket.class.name, source_id: ticket.id,
                                          cycle_key: JrcNico::Helpdesk::CycleEvidence.key(ticket), state: 'scheduled')
      expect(event.evidence.fetch('survey_id')).to eq(decision.survey_id)
      counts = [JrcRelationship::Survey.count, JrcRelationship::SurveyDispatchDecision.count, Message.count]
      process_source(event)
      JrcNico::Helpdesk::EventJob.perform_now(event.id)
      expect(event.reload.result).to include('tools' => [], 'survey_decision_id' => decision.id, 'automatic_mutation' => false)
      expect([JrcRelationship::Survey.count, JrcRelationship::SurveyDispatchDecision.count, Message.count]).to eq(counts)
      verify_shared_survey_readback(decision)
      expect(JrcNico::Helpdesk::Approval.where(event: event)).to be_empty
    end

    it 'requires current Relationship access to read the stored survey evidence' do
      event = capture_source
      sd_account.disable_features!('jrc_relationship')
      get "#{base}/events", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('events')).to be_empty
      expect(event.reload).to be_persisted
      expect(JrcRelationship::SurveyDispatchDecision.find(event.evidence.fetch('survey_decision_id'))).to be_persisted
    end
  end
end
