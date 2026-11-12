# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Common operational employees create, close and report within scope', type: :request do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures

  let(:path) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:colleague) { create(:user, name: 'Synthetic colleague') }
  let(:colleague_account_user) { create(:account_user, account: sd_account, user: colleague, role: :agent) }
  let(:colleague_membership) { create(:jrc_sd_membership, unit: sd_unit, account_user: colleague_account_user) }
  let(:team) { create(:team, account: sd_account) }
  let(:ticket) { sd_ticket(created_by_membership: colleague_membership, assignee_membership: colleague_membership, team: team) }
  let(:policy_definition) do
    definition = lc_definition
    definition['transitions'].select { |row| %w[resolve close].include?(row['action']) }.each do |row|
      row['allowed_account_roles'] = ['administrator']
      row['requirements'].merge!('note' => true, 'solution' => true, 'classification' => true, 'evidence' => true)
    end
    definition
  end

  before do
    TeamMember.create!(team: team, user: sd_user)
    lc_publish(definition: policy_definition)
  end

  it 'projects access and creation consistently for a non-admin operational employee' do
    get "#{path}/ui_context", headers: headers
    expect(response).to have_http_status(:ok)
    context = response.parsed_body
    expect(context.dig('capabilities', 'module', 'index')).to be(true)
    expect(context.dig('capabilities', 'tickets', 'index')).to be(true)
    expect(context.fetch('units').sole.dig('permissions', 'create_ticket')).to be(true)
    post "#{path}/tickets", headers: headers.merge('Idempotency-Key' => 'common-create'),
                            params: { unit_id: sd_unit.id, ticket: sd_create_attributes }, as: :json
    expect(response).to have_http_status(:created)
    created = JrcServiceDesk::Ticket.find(response.parsed_body.fetch('ticket_id'))
    expect(created.created_by_membership_id).to eq(sd_membership.id)
    expect(created.opened_at).to be_present
    expect(sd_account_user.reload.role).to eq('agent')
  end

  it 'closes a visible teammate ticket with only a reason, records the real actor, replays safely and distinguishes metrics' do
    get "#{path}/tickets/#{ticket.id}/lifecycle", headers: headers
    expect(response).to have_http_status(:ok)
    plan = response.parsed_body.fetch('closure_options').sole
    expect(plan['steps'].pluck('action')).to eq(%w[resolve close])
    mandatory_fields = plan['steps'].map { |step| step['requirements'].values_at('note', 'solution', 'evidence', 'classification') }
    expect(mandatory_fields.flatten.none?).to be(true)
    plan['steps'].each_with_index do |step, index|
      command = { rule_key: step['key'], expected_lock_version: ticket.reload.lock_version,
                  expected_policy_version_id: response.parsed_body.fetch('policy').fetch('id'),
                  closing_reason: 'Validated by the operational employee' }
      2.times do
        post "#{path}/tickets/#{ticket.id}/lifecycle", params: command, headers: headers.merge('Idempotency-Key' => "common-close-#{index}"),
                                                       as: :json
        expect(response).to have_http_status(:ok), response.body
      end
      get "#{path}/tickets/#{ticket.id}/lifecycle", headers: headers
    end
    expect(ticket.reload.status.phase).to eq('closed')
    expect(ticket.created_by_membership_id).to eq(colleague_membership.id)
    expect(ticket.assignee_membership_id).to eq(colleague_membership.id)
    expect(ticket.lifecycle_transitions.count).to eq(2)
    expect(ticket.lifecycle_transitions.pluck(:actor_membership_id).uniq).to eq([sd_membership.id])
    expect(ticket.ticket_events.where(event_type: 'lifecycle_transitioned').count).to eq(2)
    expect(Audited::Audit.where(auditable: ticket, associated: sd_unit, action: 'close').count).to eq(1)
    expect(ticket.lifecycle_transitions.last.payload['closing_reason']).to eq('Validated by the operational employee')
    get "#{path}/operational_reports", params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:ok), response.body
    report = response.parsed_body.fetch('report')
    expect(report['resolution_rate']).to eq(100.0)
    expect(report.dig('activity', 'closed_tickets')).to eq(1)
    closer = report.dig('workforce', 'items').find { |row| row['account_user_id'] == sd_account_user.id.to_s }
    expect(closer).to include('created' => 0, 'assigned' => 0, 'closed' => 1, 'closed_for_other_assignee' => 1)
    owner = report.dig('workforce', 'items').find { |row| row['account_user_id'] == colleague_account_user.id.to_s }
    expect(owner).to include('created' => 1, 'assigned' => 1, 'closed' => 0, 'closed_by_other' => 1)
  end

  it 'requires a reason from direct API callers and never duplicates an already closed ticket' do
    lc_execute(ticket, 'resolve', closing_reason: 'Resolution checked')
    command = { rule_key: 'close', expected_lock_version: ticket.reload.lock_version, expected_policy_version_id: ticket.lifecycle_policy_version_id }
    [nil, '', '   '].each_with_index do |reason, index|
      post "#{path}/tickets/#{ticket.id}/lifecycle", params: command.merge(closing_reason: reason),
                                                     headers: headers.merge('Idempotency-Key' => "empty-close-#{index}"), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(ticket.lifecycle_transitions.where(action: 'close')).not_to exist
    post "#{path}/tickets/#{ticket.id}/lifecycle", params: command.merge(closing_reason: 'Completed'),
                                                   headers: headers.merge('Idempotency-Key' => 'valid-close'), as: :json
    expect(response).to have_http_status(:ok)
    post "#{path}/tickets/#{ticket.id}/lifecycle", params: command.merge(expected_lock_version: ticket.reload.lock_version, closing_reason: 'Again'),
                                                   headers: headers.merge('Idempotency-Key' => 'duplicate-close'), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(ticket.lifecycle_transitions.where(action: 'close').count).to eq(1)
  end

  it 'keeps another unit, account and administrative configuration outside the employee scope' do
    other = sd_ticket(
      unit: sd_other_unit, status: create(:jrc_sd_status, unit: sd_other_unit),
      priority: create(:jrc_sd_priority, unit: sd_other_unit),
      created_by_membership: create(:jrc_sd_membership, unit: sd_other_unit, account_user: colleague_account_user)
    )
    get "#{path}/tickets/#{other.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    get "#{path}/operational_reports", params: { unit_id: sd_other_unit.id }, headers: headers
    expect(response).to have_http_status(:not_found)
    get "/api/v1/accounts/#{sd_foreign_account.id}/jrc_service_desk/ui_context", headers: headers
    expect(response.status).to be_in([401, 403, 404])
    get "#{path}/ui_context", headers: headers
    expect(response.parsed_body.dig('capabilities', 'settings', 'index')).to be(false)
    expect(response.parsed_body.dig('capabilities', 'lifecycle_policies', 'publish')).to be(false)
  end

  it 'denies access after an operational membership is deactivated without reactivating it' do
    sd_membership.update!(active: false)
    get "#{path}/ui_context", headers: headers
    expect(response).to have_http_status(:forbidden)
    expect(sd_membership.reload.active).to be(false)
  end
  it 'counts a closure in the selected period even when its ticket opened earlier' do
    historical = sd_ticket(opened_at: 3.days.ago, created_by_membership: colleague_membership,
                           assignee_membership: colleague_membership, team: team)
    lc_execute(historical, 'resolve', closing_reason: 'Observed period resolution')
    lc_execute(historical, 'close', closing_reason: 'Observed period closure')
    get "#{path}/operational_reports", params: { unit_id: sd_unit.id, from: 1.day.ago.iso8601 }, headers: headers
    expect(response).to have_http_status(:ok), response.body
    report = response.parsed_body.fetch('report')
    expect(report['total']).to eq(0)
    expect(report['resolution_rate']).to be_nil
    expect(report.dig('activity', 'closed_tickets')).to eq(1)
    expect(report.dig('daily_activity', 'items').sum { |row| row['closed'] }).to eq(1)
    expect(report.dig('daily_activity', 'items').sum { |row| row['backlog_change'] }).to eq(-1)
    closer = report.dig('workforce', 'items').find { |row| row['account_user_id'] == sd_account_user.id.to_s }
    expect(closer).to include('created' => 0, 'assigned' => 0, 'closed' => 1)
  end

end
