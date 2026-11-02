# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Coordinated publication concurrency', :sd_concurrency, type: :service do
  self.use_transactional_tests = false
  include JrcServiceDeskConcurrency
  include_context 'JRC Service Desk domain'

  let(:queue) { create(:jrc_sd_queue, unit: sd_unit) }
  let(:attributes) do
    { 'kind' => 'operational', 'code' => 'concurrent-composition', 'name' => 'Synthetic concurrent composition', 'description' => '', 'service_id' => nil, 'enabled' => false,
      'definition' => { 'lifecycle' => nil, 'notifications' => [], 'queues' => [], 'families' => { 'routing' => { 'rules' => [
        { 'key' => 'route', 'precedence' => 5, 'match' => { 'priority_id' => sd_priority.id }, 'output' => { 'queue_id' => queue.id } }
      ] } } } }
  end
  let(:service) { JrcServiceDesk::AutomationPublicationService.new(user_context: sd_context) }
  let(:command) do
    preview = service.preview(unit_id: sd_unit.id, attributes: attributes)
    { unit_id: sd_unit.id, attributes: attributes, expected_version: 0, expected_native_versions: preview[:native_versions], confirmed: true, idempotency_key: 'concurrent-coordinated-publication' }
  end
  before { sd_as_admin! }

  it 'commits one native version and one immutable receipt for simultaneous identical keys' do
    input = command
    actor = sd_context
    results = concurrently(Array.new(2) { -> { JrcServiceDesk::AutomationPublicationService.new(user_context: actor).call(**input).publication.id } })
    expect(results).to all(be_a(Integer))
    expect(results.uniq.size).to eq(1)
    expect(JrcServiceDesk::AutomationPublication.where(account: sd_account, unit: sd_unit).count).to eq(1)
    expect(JrcServiceDesk::OperationalRuleVersion.where(account: sd_account, unit: sd_unit).count).to eq(1)
  end

  it 'rejects one simultaneous stale update without a partial native publication' do
    input = command
    actor = sd_context
    results = concurrently(2.times.map do |number|
      -> { JrcServiceDesk::AutomationPublicationService.new(user_context: actor).call(**input.merge(idempotency_key: "competing-#{number}")).publication.id }
    end)
    expect(results.count { |value| value.is_a?(Integer) }).to eq(1)
    expect(results.count { |value| value.is_a?(JrcServiceDesk::IdempotencyConflict) }).to eq(1)
    expect(JrcServiceDesk::AutomationPublication.where(account: sd_account, unit: sd_unit).count).to eq(1)
    expect(JrcServiceDesk::OperationalRuleVersion.where(account: sd_account, unit: sd_unit).count).to eq(1)
  end

  it 'serializes a shared queue update against a coordinated publication with its expected native revision' do
    attributes['definition']['queues'] = [{ 'id' => queue.id, 'attributes' => { 'ola_targets' => { 'first_response' => 900 }, 'ola_time_basis' => 'calendar' } }]
    input = command
    revision = JrcServiceDesk::ConfigurationResources.revision('queues', queue.reload)
    actor = sd_context
    results = concurrently([
      -> { JrcServiceDesk::AutomationPublicationService.new(user_context: actor).call(**input).publication },
      -> { JrcServiceDesk::ConfigurationService.new(user_context: actor).update(resource: 'queues', record_id: queue.id,
        attributes: { 'ola_targets' => { 'first_response' => 1800 }, 'ola_time_basis' => 'calendar' }, expected_revision: revision, idempotency_key: 'competing-queue') }
    ])
    expect(results.count { |value| value.is_a?(Exception) }).to eq(1)
    expect(results.find { |value| value.is_a?(Exception) }).to be_a(JrcServiceDesk::IdempotencyConflict)
    publications = JrcServiceDesk::AutomationPublication.where(account: sd_account, unit: sd_unit)
    expect(JrcServiceDesk::OperationalRuleVersion.where(account: sd_account, unit: sd_unit).count).to eq(publications.count)
    expect(queue.policy_versions.count).to eq(1)
  end
end
