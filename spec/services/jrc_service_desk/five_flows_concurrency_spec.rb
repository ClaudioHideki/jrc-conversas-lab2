# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

RSpec.describe 'Five Service Desk flows with independent PostgreSQL connections', :sd_concurrency, type: :request do
  self.use_transactional_tests = false
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskConcurrency
  let(:root) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token }

  before { sd_as_admin! }

  def race(operations)
    results = concurrently(operations.map do |operation|
      lambda do
        pid = ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()')
        value = begin
          operation.call
        rescue StandardError => e
          e
        end
        { pid: pid, value: value }
      end
    end)
    expect(results).to all(be_a(Hash))
    expect(results.map { |row| row[:pid] }.uniq.size).to eq(operations.size)
    puts 'FIVE_FLOW_CONNECTIONS ' + results.map { |row| { pid: row[:pid], outcome: row[:value].class.name } }.to_json
    results.map { |row| row[:value] }
  end

  it 'commits one case edit and refuses the other stale HTTP update without rewriting its journal' do
    row = JrcServiceDesk::CreateIncidentService.new(user_context: sd_context).call(unit_id: sd_unit.id,
                                                                                   attributes: { title: 'Synthetic concurrent case', severity: 'normal' }, idempotency_key: 'concurrent-create')
    version = row.lock_version
    auth = headers
    path = "#{root}/case_workspaces/#{row.id}/commands"
    results = race(%w[first second].map do |title|
      lambda do
        client = ActionDispatch::Integration::Session.new(Rails.application)
        client.post(path, as: :json, headers: auth.merge('Idempotency-Key' => title), params: {
                      action: 'update', attributes: { title: title }, expected_lock_version: version
                    })
        client.response.status
      end
    end)
    expect(results.sort).to eq([200, 409])
    expect(row.incident_entries.where(event_type: 'updated').count).to eq(1)
    expect(%w[first second]).to include(row.reload.title)
  end

  it 'preserves one private draft when two PostgreSQL writers attempt its initial version' do
    ctx = sd_context
    unit = sd_unit.id
    results = race(%w[first second].map do |title|
      lambda {
        JrcServiceDesk::SaveAutomationDraftService.new(user_context: ctx).call(unit_id: unit, kind: 'queue', code: 'concurrent',
                                                                               payload: { 'name' => title }, expected_version: -1)
      }
    end)
    expect(results.count { |row| row.is_a?(JrcServiceDesk::AutomationDraft) }).to eq(1)
    expect(results.count { |row| row.class.name == 'ActiveRecord::StaleObjectError' }).to eq(1)
    expect(JrcServiceDesk::AutomationDraft.where(account: sd_account, code: 'concurrent').count).to eq(1)
  end

  it 'publishes one immutable OLA version from two competing queue revisions' do
    queue = create(:jrc_sd_queue, unit: sd_unit)
    revision = JrcServiceDesk::ConfigurationResources.revision('queues', queue)
    ctx = sd_context
    results = race(%w[first second].map do |name|
      lambda {
        JrcServiceDesk::ConfigurationService.new(user_context: ctx).update(resource: 'queues', record_id: queue.id,
                                                                           attributes: { name: name, ola_targets: { 'first_response' => 60, 'update' => 120, 'resolution' => 600 }, ola_time_basis: 'calendar' }, expected_revision: revision, idempotency_key: name)
      }
    end)
    expect(results.count { |row| row.is_a?(JrcServiceDesk::ConfigurationService::Result) }).to eq(1)
    expect(results.count { |row| row.class.name == 'JrcServiceDesk::IdempotencyConflict' }).to eq(1)
    expect(queue.reload.policy_versions.count).to eq(1)
    expect(queue.current_policy_version.definition['name']).to eq(queue.name)
  end

  it 'keeps multichannel publication atomic when two callers race on the same expected versions' do
    fixture_key = SecureRandom.uuid
    email = create(:channel_email, account: sd_account, email: "ola-#{fixture_key}@disposable-mail.invalid",
                                   forward_to_email: "ola-forward-#{fixture_key}@disposable-mail.invalid")
    whatsapp = create(:channel_twilio_sms, account: sd_account, medium: :whatsapp)
    controls = { 'conditions' => { 'operator' => 'all', 'items' => [] }, 'channel_order' => %w[email whatsapp],
                 'multichannel_mode' => 'all_explicit', 'additional_contact_ids' => [], 'internal_copy_member_ids' => [], 'window' => { 'enabled' => false }, 'outside_window' => 'defer', 'max_attempts' => 1, 'backoff_minutes' => 10 }
    attributes = { event_type: 'ticket_created', channel: 'email', enabled: true, confirmed: true, expected_version: 0, settings: controls,
                   channel_configurations: { 'email' => { inbox_id: email.inbox.id, template: 'Email {{number}}', template_version: 'v1' }, 'whatsapp' => { inbox_id: whatsapp.inbox.id, template: 'WhatsApp {{number}}', template_version: 'v1' } }, expected_versions: { 'email' => 0, 'whatsapp' => 0 } }
    ctx = sd_context
    unit = sd_unit.id
    results = race(2.times.map do
      lambda {
        JrcServiceDesk::PublishNotificationPolicyService.new(user_context: ctx).call(unit_id: unit, attributes: attributes.deep_dup)
      }
    end)
    expect(results.count { |row| row.is_a?(JrcServiceDesk::NotificationPolicyVersion) }).to eq(1)
    expect(results.count { |row| row.class.name == 'JrcServiceDesk::IdempotencyConflict' }).to eq(1)
    expect(JrcServiceDesk::NotificationPolicyVersion.where(unit: sd_unit).pluck(:channel).sort).to eq(%w[email whatsapp])
  end
end
