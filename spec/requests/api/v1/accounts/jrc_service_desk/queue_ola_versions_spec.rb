# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Versioned queue OLA and private drafts', type: :request do
  include_context 'JRC Service Desk domain'
  include ActiveSupport::Testing::TimeHelpers
  let(:root) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:queue) { create(:jrc_sd_queue, unit: sd_unit) }
  let(:ticket) { sd_ticket(queue: queue) }
  let(:targets) { { 'first_response' => 60, 'update' => 120, 'resolution' => 600 } }
  let(:settings) { { ola_targets: targets, ola_time_basis: 'calendar', ola_pause_waiting: true } }
  let(:command) { JrcServiceDesk::ConfigurationService.new(user_context: sd_context) }

  before { sd_as_admin! }

  def publish_queue(attributes = settings)
    command.update(resource: 'queues', record_id: queue.id, attributes: attributes,
                   expected_revision: JrcServiceDesk::ConfigurationResources.revision('queues', queue.reload), idempotency_key: SecureRandom.uuid).record.tap { queue.reload }
  end

  it 'publishes immutable versions and does not start clocks or routing merely by saving a queue' do
    publish_queue
    first = queue.reload.current_policy_version
    expect(first.definition['ola_targets']).to eq(targets)
    expect(JrcServiceDesk::OlaClock.count).to eq(0)
    expect(queue.distribution_mode).to eq('manual')
    expect { first.update!(definition: {}, digest: JrcServiceDesk::CanonicalJson.digest({})) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    publish_queue(settings.merge(ola_targets: targets.merge('resolution' => 900)))
    expect(queue.reload.policy_versions.count).to eq(2)
    expect(first.reload.definition['ola_targets']['resolution']).to eq(600)
  end

  it 'starts three independent native clocks without creating a customer SLA snapshot' do
    publish_queue
    JrcServiceDesk::OlaTracker.sync!(ticket)
    expect(ticket.ola_clocks.pluck(:kind).sort).to eq(%w[first_response resolution update])
    expect(ticket.ola_clocks.pluck(:entry_key).uniq.size).to eq(1)
    expect(ticket.ola_clocks.pluck(:budget_seconds).sort).to eq([60, 120, 600])
    expect(ticket.sla_snapshots.count).to eq(0)
    2.times { JrcServiceDesk::OlaTracker.sync!(ticket) }
    expect(ticket.ola_clocks.count).to eq(3)
  end

  it 'does not change existing budgets or snapshots on republication' do
    publish_queue
    JrcServiceDesk::OlaTracker.sync!(ticket)
    frozen = ticket.ola_clocks.order(:id).map(&:attributes)
    publish_queue(settings.merge(ola_targets: targets.merge('resolution' => 900)))
    expect(ticket.ola_clocks.order(:id).map(&:attributes)).to eq(frozen)
  end

  it 'pauses and resumes all internal measurements using their frozen rules' do
    travel_to(Time.utc(2026, 10, 24, 10)) do
      publish_queue
      JrcServiceDesk::OlaTracker.sync!(ticket)
      waiting = create(:jrc_sd_status, unit: sd_unit, phase: 'waiting', initial: false)
      ticket.update!(status: waiting)
      JrcServiceDesk::OlaTracker.sync!(ticket, now: 10.seconds.from_now)
      expect(ticket.ola_clocks.pluck(:state).uniq).to eq(['paused'])
      ticket.update!(status: sd_status)
      JrcServiceDesk::OlaTracker.sync!(ticket, now: 100.seconds.from_now)
      expect(ticket.ola_clocks.pluck(:elapsed_seconds).map(&:to_i).uniq).to eq([10])
      expect(ticket.ola_clocks.find_by!(kind: 'first_response').due_at).to eq(150.seconds.from_now)
    end
  end

  it 'records a real accepted reply once and starts the next update interval without fabricating customer SLA' do
    publish_queue
    JrcServiceDesk::OlaTracker.sync!(ticket)
    inbox = create(:inbox, :with_email, account: sd_account)
    conversation = create(:conversation, account: sd_account, inbox: inbox, contact: sd_contact, assignee: sd_user)
    JrcServiceDesk::TicketConversation.create!(account: sd_account, unit: sd_unit, ticket: ticket, conversation: conversation,
                                               linked_by_membership: sd_membership)
    message = create(:message, account: sd_account, conversation: conversation, sender: sd_user, message_type: :outgoing,
                               content: 'Synthetic accepted reply', source_id: 'synthetic-provider')
    2.times { JrcServiceDesk::NativeResponseRecorder.new(message, evidence: JrcServiceDesk::NativeResponseRecorder.evidence(message.reload)).call }
    expect(ticket.ola_clocks.where(kind: 'first_response').pluck(:state)).to eq(['completed'])
    expect(ticket.ola_clocks.where(kind: 'update').order(:id).pluck(:state)).to eq(%w[completed running])
    expect(ticket.sla_cycles.count).to eq(0)
    expect(ticket.ticket_events.where(event_type: 'resource_updated').count).to eq(1)
  end

  it 'does not count an internal note or assignment as first response' do
    publish_queue
    JrcServiceDesk::OlaTracker.sync!(ticket)
    ticket.update!(assignee_membership: sd_membership)
    JrcServiceDesk::OlaTracker.sync!(ticket)
    expect(ticket.ola_clocks.find_by!(kind: 'first_response').state).to eq('running')
  end

  it 'completes resolution while stopping unachieved response/update clocks at resolution' do
    publish_queue
    JrcServiceDesk::OlaTracker.sync!(ticket)
    ticket.update!(status: create(:jrc_sd_status, unit: sd_unit, phase: 'resolved', initial: false))
    JrcServiceDesk::OlaTracker.sync!(ticket)
    expect(ticket.ola_clocks.find_by!(kind: 'resolution').state).to eq('completed')
    expect(ticket.ola_clocks.find_by!(kind: 'first_response').state).to eq('stopped')
  end

  it 'preserves all prior intervals on queue transfer' do
    publish_queue
    JrcServiceDesk::OlaTracker.sync!(ticket)
    second = create(:jrc_sd_queue, unit: sd_unit)
    command.update(resource: 'queues', record_id: second.id, attributes: settings,
                   expected_revision: JrcServiceDesk::ConfigurationResources.revision('queues', second), idempotency_key: SecureRandom.uuid)
    JrcServiceDesk::TransferTicketService.new(user_context: sd_context).call(ticket_id: ticket.id,
                                                                             attributes: { queue_id: second.id }, expected_lock_version: ticket.lock_version)
    expect(ticket.ola_clocks.where(queue: queue).pluck(:state).uniq).to eq(['stopped'])
    expect(ticket.ola_clocks.where(queue: second).pluck(:state).uniq).to eq(['running'])
  end

  it 'persists and rereads a private draft without publishing and rejects a stale update' do
    payload = { unit_id: sd_unit.id, kind: 'queue', code: queue.id.to_s, payload: { form: { name: 'Synthetic draft' } }, expected_version: -1 }
    put "#{root}/automation_drafts", params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('draft', 'payload', 'form', 'name')).to eq('Synthetic draft')
    expect(queue.reload.policy_versions.count).to eq(0)
    get "#{root}/automation_drafts", params: payload.slice(:unit_id, :kind, :code), headers: headers
    expect(response.parsed_body.dig('draft', 'lock_version')).to eq(0)
    put "#{root}/automation_drafts", params: payload.merge(payload: { form: { name: 'stale' } }), headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
  end

  it 'denies unauthorized and cross-account drafts and version reads without changing data' do
    sd_account_user.update!(role: :agent)
    put "#{root}/automation_drafts", params: { unit_id: sd_unit.id, kind: 'queue', code: 'new', payload: {}, expected_version: -1 },
                                     headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(JrcServiceDesk::AutomationDraft.count).to eq(0)
    sd_as_admin!
    get "#{root}/queue_policy_versions", params: { unit_id: sd_foreign_unit.id, queue_id: queue.id }, headers: headers
    expect(response).to have_http_status(:not_found)
  end
end
