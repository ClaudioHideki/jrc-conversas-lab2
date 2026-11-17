# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'CP6 lifecycle field visibility' do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures

  def restricted_grants(*keys)
    skip 'Native CustomRole extension unavailable; this case remains pending' unless defined?(::CustomRole) && sd_account_user.respond_to?(:custom_role)
    role = CustomRole.create!(account: sd_account, name: SecureRandom.hex(8), permissions: keys.map { |key| "jrc_service_desk_#{key}" })
    sd_account_user.update!(custom_role: role)
  end

  it 'redacts lifecycle notes, evidence and SLA from history-only readers' do
    lc_publish
    row = sd_ticket
    note = JrcServiceDesk::AddNoteService.new(user_context: sd_context).call(ticket_id: row.id, attributes: { body: 'Private evidence' }, idempotency_key: SecureRandom.uuid)
    event = lc_execute(row, 'resolve', note: 'Private resolution', solution: 'Private solution', evidence_note_ids: [note.id])
    restricted_grants('module_view', 'tickets_view', 'history_view')
    projection = JrcServiceDesk::LifecycleReadService.new(user_context: sd_context, ticket: row.reload).transition(event)
    expect(projection[:payload].keys).not_to include('note', 'solution', 'fields', 'evidence_note_ids', 'sla')
    expect(projection[:payload]['to_phase']).to eq('resolved')
    expect(event.reload.payload['note']).to eq('Private resolution')
  end

  it 'rejects protected input without note visibility and performs no partial transition' do
    lc_publish
    row = sd_ticket
    restricted_grants('module_view', 'tickets_view', 'history_view', 'sla_view', 'resolve')
    expect { lc_execute(row, 'resolve', note: 'Unauthorized protected content') }.to raise_error(Pundit::NotAuthorizedError)
    expect(row.reload.status_id).to eq(sd_status.id)
    expect(row.lifecycle_transitions).to be_empty
    expect(row.ticket_events).to be_empty
  end

  it 'offers manual resolution without protected evidence while keeping legacy requirements and note privacy intact' do
    definition = lc_definition
    definition['transitions'].find { |r| r['action'] == 'resolve' }['requirements']['note'] = true
    lc_publish(definition: definition)
    row = sd_ticket
    restricted_grants('module_view', 'tickets_view', 'history_view', 'sla_view', 'resolve')
    data = JrcServiceDesk::LifecycleReadService.new(user_context: sd_context, ticket: row).call
    resolve = data[:options].find { |rule| rule[:action] == 'resolve' }
    expect(resolve).to be_present
    expect(resolve[:requirements]).to include('note' => false, 'evidence' => false, 'fields' => {})
    expect { lc_execute(row, 'resolve') }.to raise_error(Pundit::NotAuthorizedError)
    expect(row.reload.status_id).to eq(sd_status.id)
    result = lc_execute(row, 'resolve', operational_closure: true)
    expect(row.reload.status.phase).to eq('resolved')
    expect(result.payload).not_to have_key('note')
  end

  it 'keeps creation permission separate from the configured initial status' do
    sd_as_admin!
    data = JrcServiceDesk::UiContextService.new(user_context: sd_context).call
    expect(data[:units].first[:initial_status]).to be_nil
    expect(data[:units].first[:permissions][:create_ticket]).to be(true)
    sd_status
    data = JrcServiceDesk::UiContextService.new(user_context: sd_context).call
    expect(data[:units].first[:permissions][:create_ticket]).to be(true)
  end
end
