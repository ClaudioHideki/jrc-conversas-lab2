# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'Versioned unit/service lifecycle policies', type: :service do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures

  it 'denies without a policy, including native administrator' do
    row = sd_ticket; sd_as_admin!
    expect(JrcServiceDesk::LifecycleActionPolicy.new(sd_context, row).apply?).to be(false)
    expect { lc_execute(row, 'resolve') }.to raise_error(Pundit::NotAuthorizedError)
    expect(row.reload.lifecycle_policy_version_id).to be_nil
  end

  it 'selects unit default and prefers an explicitly configured service policy' do
    unit_policy = lc_publish
    sd_as_admin!
    service = JrcServiceDesk::CreateServiceDefinitionService.new(user_context: sd_context).call(unit_id: sd_unit.id,
      attributes: { name: 'Service fixture', code: 'srv-fixture', active: true })
    row = sd_ticket(service: service)
    expect(JrcServiceDesk::LifecycleSelector.new(row).applicable.id).to eq(unit_policy.current_version_id)
    specific = lc_publish(service: service)
    expect(JrcServiceDesk::LifecycleSelector.new(row.reload).applicable.id).to eq(specific.current_version_id)
    lc_publish(service: service, enabled: false, expected_version: 1)
    expect(JrcServiceDesk::LifecycleSelector.new(row.reload).applicable).to be_nil
  end

  it 'binds creation, pins old tickets to immutable v1, and publishes v2 only for future selection' do
    policy = lc_publish
    row = JrcServiceDesk::CreateTicketWorkflowService.new(user_context: sd_context).call(
      unit_id: sd_unit.id, attributes: sd_create_attributes, idempotency_key: 'pin-v1')
    first = row.lifecycle_policy_version
    digest = first.digest
    second_policy = lc_publish(expected_version: 1)
    expect(row.reload.lifecycle_policy_version_id).to eq(first.id)
    expect(JrcServiceDesk::LifecycleSelector.new(row).applicable.id).to eq(first.id)
    expect(first.reload.digest).to eq(digest)
    expect { first.update!(definition: {}) }.to raise_error(ActiveRecord::RecordInvalid)
    first.reload
    first.publication = first.publication.merge('name' => 'Attempted rewrite')
    first.digest = first.expected_digest
    expect { first.save! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect(first.reload.digest).to eq(digest)
    expect(second_policy.current_version.version).to eq(2)
    expect(second_policy.current_version.publication).to include('enabled' => true, 'name' => 'Explicit fixture policy')
    expect { row.update!(lifecycle_policy_version: second_policy.current_version) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'rejects conflicting publications without replacing the current version' do
    row = lc_publish
    expect { lc_publish(expected_version: 0) }.to raise_error(JrcServiceDesk::IdempotencyConflict)
    expect(row.reload.current_version.version).to eq(1)
    expect(row.versions.count).to eq(1)
  end

  it 'rejects publication by agent or native administrator without the unit grant' do
    lc_statuses
    command = JrcServiceDesk::PublishLifecyclePolicyService.new(user_context: sd_context)
    attrs = { name: 'Denied', enabled: true, expected_version: 0, definition: lc_definition }
    expect { command.call(unit_id: sd_unit.id, attributes: attrs) }.to raise_error(Pundit::NotAuthorizedError)
    sd_as_admin!
    expect { command.call(unit_id: sd_other_unit.id, attributes: attrs) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { command.call(unit_id: sd_foreign_unit.id, attributes: attrs) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'rejects status IDs from another unit or Account and unknown rule fields' do
    bad = lc_definition
    bad['transitions'].first['to_status_id'] = create(:jrc_sd_status, unit: sd_foreign_unit).id
    expect { lc_publish(definition: bad) }.to raise_error(ActiveRecord::RecordNotFound)
    bad = lc_definition; bad['transitions'].first['grant_admin'] = true
    expect { lc_publish(definition: bad) }.to raise_error(ArgumentError)
  end
end
