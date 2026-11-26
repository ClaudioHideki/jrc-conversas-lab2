# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Original-agent authenticated Service Desk ending admission and native job execution', type: :request do
  self.use_transactional_tests = false
  include_context 'with native ending rule configuration'
  include_context 'JRC Service Desk domain'

  let(:sd_account) { account }
  let(:sd_user) { actor }
  let(:sd_account_user) { member }
  let(:headers) { actor.create_new_auth_token }
  let(:path) { "/api/v1/accounts/#{account.id}/jrc_contact_center/acw_policy/ending_rules" }
  let(:sd_parameters) do
    { 'unit_id' => sd_unit.id.to_s, 'service_id' => nil,
      'attributes' => { 'title' => 'SYNTHETIC private ticket template', 'description' => 'SYNTHETIC reviewed description',
                        'status_id' => sd_status.id.to_s, 'priority_id' => sd_priority.id.to_s } }
  end
  let(:sd_rule) do
    rule_input.merge('destination_schema_version' => 2, 'execution_mode' => 'agent_confirmation',
                     'actions' => [{ 'kind' => 'service_desk', 'parameters' => sd_parameters }])
  end

  before do
    # Explicit synthetic grants make operational membership revocation meaningful.
    # Native administrators without a custom role retain their native SD access.
    account.enable_features!('custom_roles')
    rights = %w[jrc_contact_center_view jrc_contact_center_configure jrc_service_desk_module_view jrc_service_desk_tickets_view
                jrc_service_desk_tickets_create jrc_service_desk_lookups_view jrc_service_desk_customers_view
                jrc_projects_project_view jrc_projects_project_create jrc_projects_task_create jrc_projects_task_view
                jrc_projects_task_assign jrc_projects_task_update jrc_projects_member_view]
    member.update!(custom_role: create(:custom_role, account: account, permissions: rights))
    sd_membership
    business.update!(settings: business.settings.merge('service_desk_unit_id' => sd_unit.id.to_s))
    sd_rule
  end

  def save_service_desk_rule(input = sd_rule, revision: :current)
    account.reload
    expected = revision == :current ? policy.revision : revision
    post path, headers: headers, params: { private_rule: input, expected_revision: expected }, as: :json
  end

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned independent native Service Desk request transactions required' unless owned && !ApplicationRecord.connection.transaction_open?

    example.run
  end

  def prepare_native_sd_attendance
    save_service_desk_rule
    expect(response).to have_http_status(:ok)
    account.reload
    JrcContactCenter::EndingActions::ActivateRule.new(
      account: account, member: member, rule_code: sd_rule.fetch('code'), request_key: SecureRandom.uuid,
      expected_revision: JrcContactCenter::AcwPolicy.new(account: account).revision
    ).call
    native_sd_original_agent!
    native_sd_source_attendance
  end

  def native_sd_original_agent!
    rights = (member.custom_role.permissions - ['jrc_contact_center_configure']) + ['jrc_contact_center_operate']
    member.custom_role.update!(permissions: rights.uniq)
    member.update!(role: :agent)
    JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member, active: true, role: 'agent', priority: 1)
  end

  def native_sd_source_attendance
    contact = create(:contact, account: account, name: 'SYNTHETIC native SD original requester', company_id: nil)
    call = JrcContactCenter::CallSession.create!(
      account: account, provider: 'synthetic', correlation_id: SecureRandom.uuid, contact_id: contact.id,
      direction: 'inbound', status: 'connected', started_at: Time.current, answered_at: Time.current,
      current_unit: queue.unit, current_queue: queue
    )
    JrcContactCenter::CallLeg.create!(account: account, call_session: call, account_user: member, queue: queue,
                                      direction: 'inbound', status: 'connected', started_at: call.started_at, answered_at: call.answered_at)
    call.update!(status: 'ended', ended_at: Time.current)
    JrcContactCenter::Qualification.find_by!(account: account, account_user: member, call_session: call)
  end

  def confirmed_native_sd_endpoint(row)
    endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/qualifications/#{row.id}"
    post "#{endpoint}/confirm_reason", headers: headers, as: :json, params: {
      qualification: { reason_code: sd_rule.fetch('reason_code') },
      expected_draft_revision: JrcContactCenter::QualificationDraftRevision.token(row), idempotency_key: SecureRandom.uuid
    }
    expect(response).to have_http_status(:ok)
    "#{endpoint}/ending_destinations"
  end

  def native_sd_admission_payload(choice)
    {
      origin_id: choice.fetch('origin_id'), rule_code: choice.fetch('rule_code'), destination_kind: 'service_desk',
      request_key: SecureRandom.uuid, review: { confirmed: true, expected_readiness_id: choice.fetch('readiness_id'),
                                                expected_version_id: choice.fetch('version_id'), expected_rule_sha256: choice.fetch('rule_sha256') }
    }
  end

  def request_native_sd_destination(row)
    endpoint = confirmed_native_sd_endpoint(row)
    get endpoint, headers: headers
    expect(response).to have_http_status(:ok)
    choice = response.parsed_body.fetch('items').sole
    expect(choice.fetch('destination_kind')).to eq('service_desk')
    post endpoint, headers: headers, as: :json, params: native_sd_admission_payload(choice)
    expect(response).to have_http_status(:accepted)
    JrcContactCenter::EndingDestinationAttempt.where(account: account).find(response.parsed_body.fetch('attempt_id'))
  end

  it 'creates one native ticket as the original agent through the real API and job while leaving ACW open' do
    row = prepare_native_sd_attendance
    attempt = request_native_sd_destination(row)
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
    # This is actual native job/service/PG execution, not a Redis-dequeue claim.
    2.times { JrcContactCenter::EndingDestinationJob.perform_now(account.id, attempt.id) }
    ticket = JrcServiceDesk::Ticket.where(account: account).sole
    expect(member.reload).to be_agent
    expect(ticket).to have_attributes(unit_id: sd_unit.id, requester_id: row.call_session.contact_id,
                                      created_by_membership_id: sd_membership.id)
    expect(attempt.reload).to have_attributes(
      outcome: have_attributes(outcome: 'succeeded', result_code: 'completed'),
      execution: have_attributes(target_type: 'JrcServiceDesk::Ticket', target_id: ticket.id)
    )
    expect(ticket.ticket_events.where(event_type: 'ticket_created').count).to eq(1)
    expect(JrcContactCenter::EndingDestinationExecution.where(account: account).count).to eq(1)
    expect(row.reload.completed_at).to be_nil
  end

  it 'withdraws current native destination authority after admission before running the job instead of borrowing configuration rights' do
    row = prepare_native_sd_attendance
    attempt = request_native_sd_destination(row)
    rights = member.custom_role.permissions - ['jrc_service_desk_tickets_create']
    member.custom_role.update!(permissions: rights)
    JrcContactCenter::EndingDestinationJob.perform_now(account.id, attempt.id)
    expect(attempt.reload.outcome.outcome).to eq('blocked')
    expect(attempt.execution).to be_nil
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
    expect(row.reload.completed_at).to be_nil
  end

  it 'revalidates current native unit membership after admission without creating a ticket or completing the original ACW' do
    row = prepare_native_sd_attendance
    attempt = request_native_sd_destination(row)
    sd_membership.update!(active: false)
    JrcContactCenter::EndingDestinationJob.perform_now(account.id, attempt.id)
    expect(attempt.reload.outcome.outcome).to eq('blocked')
    expect(attempt.execution).to be_nil
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
    expect(row.reload.completed_at).to be_nil
  end
end
