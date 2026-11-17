# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Manual closure without configuration blockers', type: :request do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  include ActiveSupport::Testing::TimeHelpers

  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:definition) do
    value = lc_definition(tracked: true)
    value['sla'].merge!('obligation' => 'contractual', 'missing_configuration' => 'block')
    value['transitions'].select { |rule| %w[resolve close].include?(rule['action']) }.each do |rule|
      rule['allowed_account_roles'] = ['administrator']
      rule['end_pause'] = false if rule['action'] == 'close'
      rule['requirements'].merge!('note' => true, 'solution' => true, 'evidence' => true, 'classification' => true,
        'fields' => { 'approved' => { 'type' => 'boolean', 'label' => 'Approval', 'required' => true, 'equals' => true } })
    end
    value
  end

  before do
    travel_to Time.iso8601('2026-11-17T12:00:00Z')
    lc_publish(definition: definition)
  end
  after { travel_back }

  it 'allows a ticket viewer to close despite missing SLA, approval, role and evidence requirements, without exposing private history' do
    service = JrcServiceDesk::Service.create!(account: sd_account, unit: sd_unit, code: 'approval', name: 'Approval service', active: true, approval_required: true)
    ticket = sd_ticket(service: service)
    role = create(:custom_role, account: sd_account, permissions: %w[jrc_service_desk_module_view jrc_service_desk_tickets_view])
    sd_account_user.update!(custom_role: role)
    allow(JrcNico::Helpdesk::Capture).to receive(:call).and_raise(Pundit::NotAuthorizedError, 'No access to optional NICO integration')
    travel 20.minutes
    get "#{base}/tickets/#{ticket.id}/lifecycle", headers: headers
    expect(response).to have_http_status(:ok), response.body
    data = response.parsed_body
    expect(data.fetch('closure_options').sole.fetch('steps').pluck('action')).to eq(%w[resolve close])
    expect(data['history']).to be_empty
    expect(data['measurement']).to be_nil
    policy = data.fetch('policy').fetch('id')
    %w[resolve close].each do |action|
      command = { rule_key: action, operational_closure: true, expected_lock_version: ticket.reload.lock_version,
                  expected_policy_version_id: policy }
      2.times do
        post "#{base}/tickets/#{ticket.id}/lifecycle", headers: headers.merge('Idempotency-Key' => "manual-#{action}"), as: :json,
          params: command
        expect(response).to have_http_status(:ok), response.body
        get "#{base}/tickets/#{ticket.id}/lifecycle/transitions/#{response.parsed_body.fetch('result_id')}", headers: headers
        expect(response).to have_http_status(:ok), response.body
      end
    end
    expect(ticket.reload.status.phase).to eq('closed')
    expect(ticket.lifecycle_transitions.count).to eq(2)
    expect(ticket.lifecycle_transitions.pluck(:actor_membership_id).uniq).to eq([sd_membership.id])
    expect(ticket.lifecycle_transitions.all? { |row| row.payload.dig('sla', 'calculation_pending') }).to be(true)
    expect(ticket.sla_cycles).to be_empty
    expect(Audited::Audit.where(auditable: ticket, action: 'close').count).to eq(1)
    get "#{base}/tickets/#{ticket.id}/lifecycle", headers: headers
    expect(response.parsed_body.fetch('history')).to be_empty
    expect(response.parsed_body['cycle']).to be_nil
    sd_account_user.update!(custom_role: nil)
    get "#{base}/tickets/#{ticket.id}/lifecycle", headers: headers
    expect(response.parsed_body.dig('measurement', 'closure', 'elapsed_seconds')).to eq(1200)
    get "#{base}/dashboard", headers: headers
    expect(response.parsed_body.dig('dashboard', 'phases', 'closed')).to eq(1)
    expect(response.parsed_body.dig('dashboard', 'supervision', 'sla_coverage', 'tickets_with_pending_result')).to eq(1)
  end

  it 'completes the real resolution clock with configured targets and preserves the measured breach' do
    ticket = sd_ticket
    lc_snapshot(ticket)
    lc_execute(ticket, 'work_status')
    before = ticket.sla_cycles.sole.sla_clocks.order(:kind).pluck(:kind, :budget_seconds, :due_at)
    travel 2.days
    %w[resolve close].each do |action|
      post "#{base}/tickets/#{ticket.id}/lifecycle", headers: headers.merge('Idempotency-Key' => "measured-#{action}"), as: :json,
        params: { rule_key: action, operational_closure: true, expected_lock_version: ticket.reload.lock_version,
                  expected_policy_version_id: JrcServiceDesk::LifecycleSelector.new(ticket).applicable.id }
      expect(response).to have_http_status(:ok), response.body
    end
    clocks = ticket.sla_cycles.sole.sla_clocks
    expect(clocks.order(:kind).pluck(:kind, :budget_seconds, :due_at)).to eq(before)
    expect(clocks.find_by!(kind: 'resolution')).to have_attributes(state: 'completed')
    expect(clocks.find_by!(kind: 'resolution').met?).to be(false)
    expect(clocks.find_by!(kind: 'first_response')).to have_attributes(state: 'stopped', achieved_at: nil)
  end

  it 'does not let an automated executor use the manual closure override' do
    ticket = sd_ticket
    expect do
      JrcServiceDesk::LifecycleTransitionService.new(user_context: sd_context).call(ticket_id: ticket.id,
        attributes: { rule_key: 'resolve', operational_closure: true, expected_lock_version: 0,
                      expected_policy_version_id: JrcServiceDesk::LifecycleSelector.new(ticket).applicable.id },
        idempotency_key: 'automated-override', execution_command: Object.new)
    end.to raise_error(Pundit::NotAuthorizedError)
    expect(ticket.reload.status.phase).to eq('open')
  end

  it 'keeps inaccessible tickets inaccessible even with the manual flag' do
    ticket = sd_ticket(unit: sd_other_unit, status: create(:jrc_sd_status, unit: sd_other_unit), priority: create(:jrc_sd_priority, unit: sd_other_unit),
      created_by_membership: create(:jrc_sd_membership, unit: sd_other_unit))
    post "#{base}/tickets/#{ticket.id}/lifecycle", headers: headers.merge('Idempotency-Key' => 'outside-unit'), as: :json,
      params: { rule_key: 'resolve', operational_closure: true, expected_lock_version: 0, expected_policy_version_id: 1 }
    expect(response).to have_http_status(:not_found)
    expect(ticket.reload.status.phase).to eq('open')
  end
end
