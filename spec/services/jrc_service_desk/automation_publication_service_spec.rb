# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk::AutomationPublicationService do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures

  let(:queue) { create(:jrc_sd_queue, unit: sd_unit) }
  let(:service) { described_class.new(user_context: sd_context) }
  let(:attributes) do
    { 'kind' => 'operational', 'code' => 'explicit-routing', 'name' => 'Synthetic routing', 'description' => 'Test only',
      'service_id' => nil, 'enabled' => false,
      'definition' => { 'lifecycle' => nil, 'queues' => [], 'notifications' => [],
        'families' => { 'routing' => { 'rules' => [{ 'key' => 'route', 'precedence' => 10,
          'match' => { 'priority_id' => sd_priority.id }, 'output' => { 'queue_id' => queue.id } }] } } } }
  end
  let(:preview) { service.preview(unit_id: sd_unit.id, attributes: attributes) }
  let(:command) do
    { unit_id: sd_unit.id, attributes: attributes, expected_version: 0, expected_native_versions: preview.fetch(:native_versions),
      confirmed: true, idempotency_key: 'explicit-publication-1' }
  end

  before { sd_as_admin! }

  it 'validates and simulates without any writes, jobs, membership creation, audit, tasks or messages' do
    attributes
    sd_membership.update!(active: false)
    before_counts = [JrcServiceDesk::AutomationPublication, JrcServiceDesk::OperationalRuleVersion, JrcServiceDesk::UnitMembership,
                     Audited::Audit, JrcServiceDesk::Ticket, JrcServiceDesk::TicketTask, Message].map(&:count)
    result = service.preview(unit_id: sd_unit.id, attributes: attributes, facts: { 'priority_id' => sd_priority.id })
    expect(result[:valid]).to be(true)
    expect(result[:effects].values).to all(be(false))
    expect([JrcServiceDesk::AutomationPublication, JrcServiceDesk::OperationalRuleVersion, JrcServiceDesk::UnitMembership,
            Audited::Audit, JrcServiceDesk::Ticket, JrcServiceDesk::TicketTask, Message].map(&:count)).to eq(before_counts)
  end

  it 'stores a disabled immutable receipt and relinks the actual native version, without enabling execution' do
    result = service.call(**command)
    row = result.publication.reload
    expect(row.digest).to eq(row.expected_digest)
    expect(row.native_versions['families']['routing']).to eq(1)
    expect(JrcServiceDesk::OperationalRuleVersion.last.enabled).to be(false)
    expect(JrcServiceDesk::OperationalRuleVersion.last.definition['rules'].first['enabled']).to be(false)
    expect(row).to be_readonly
    expect(Audited::Audit.find(result.audit_id).auditable).to eq(row)
  end

  it 'replays the same command exactly once and rejects another payload with its key' do
    first = service.call(**command)
    expect(service.call(**command).publication.id).to eq(first.publication.id)
    expect(JrcServiceDesk::OperationalRuleVersion.count).to eq(1)
    expect do
      service.call(**command.merge(attributes: attributes.merge('name' => 'Another name')))
    end.to raise_error(JrcServiceDesk::IdempotencyConflict)
  end

  it 'rechecks management permissions when replaying a formerly authorized publication' do
    service.call(**command)
    sd_account_user.update!(role: :agent)
    expect { service.call(**command) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rejects a stale native version without creating a partial receipt' do
    version = preview[:native_versions]
    JrcServiceDesk::PublishOperationalRulesService.new(user_context: sd_context).call(unit_id: sd_unit.id, kind: 'routing',
      definition: attributes['definition']['families']['routing'], enabled: false, expected_version: 0)
    expect { service.call(**command.merge(expected_native_versions: version)) }.to raise_error(JrcServiceDesk::IdempotencyConflict)
    expect(JrcServiceDesk::AutomationPublication.count).to eq(0)
    expect(JrcServiceDesk::OperationalRuleVersion.count).to eq(1)
  end

  it 'rolls back native publications if writing the final audit receipt fails' do
    input = command
    audits_before = Audited::Audit.count
    allow_any_instance_of(JrcServiceDesk::ConfigurationAudit).to receive(:write!).and_raise(ActiveRecord::StatementInvalid, 'synthetic receipt failure')
    expect { service.call(**input) }.to raise_error(ActiveRecord::StatementInvalid, 'synthetic receipt failure')
    expect(JrcServiceDesk::AutomationPublication.count).to eq(0)
    expect(JrcServiceDesk::OperationalRuleVersion.count).to eq(0)
    expect(Audited::Audit.count).to eq(audits_before)
  end

  it 'rejects queues outside the authorized unit and Account' do
    [sd_other_unit, sd_foreign_unit].each do |unit|
      attributes['definition']['families']['routing']['rules'].first['output']['queue_id'] = create(:jrc_sd_queue, unit: unit).id
      expect { service.preview(unit_id: sd_unit.id, attributes: attributes) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  it 'blocks implicit global matching and non-positive visual precedence' do
    attributes['definition']['families']['routing']['rules'].first['match'] = {}
    expect { preview }.to raise_error(ArgumentError)
    attributes['definition']['families']['routing']['rules'].first['match'] = { 'priority_id' => sd_priority.id }
    attributes['definition']['families']['routing']['rules'].first['precedence'] = 0
    expect { service.preview(unit_id: sd_unit.id, attributes: attributes) }.to raise_error(ArgumentError)
  end

  it 'publishes lifecycle and routing together and preserves historical ticket bindings' do
    original = lc_publish
    ticket = sd_ticket(lifecycle_policy_version: original.current_version)
    attributes['kind'] = 'lifecycle'
    attributes['definition']['lifecycle'] = lc_definition
    original_id = ticket.lifecycle_policy_version_id
    result = service.call(**command)
    expect(result.publication.native_versions['lifecycle']).to eq(2)
    expect(ticket.reload.lifecycle_policy_version_id).to eq(original_id)
    expect(ticket.sla_cycles.count).to eq(0)
  end

  it 'preserves unrelated disabled native rules when adding this composition' do
    definition = { 'rules' => [{ 'key' => 'legacy', 'precedence' => 1, 'match' => {}, 'output' => { 'queue_id' => queue.id } }] }
    JrcServiceDesk::PublishOperationalRulesService.new(user_context: sd_context).call(unit_id: sd_unit.id, kind: 'routing', definition: definition,
      enabled: false, expected_version: 0)
    attributes['enabled'] = true
    service.call(**command)
    latest = JrcServiceDesk::OperationalRuleVersion.last
    expect(latest.definition['rules'].find { |row| row['key'] == 'legacy' }['enabled']).to be(false)
    expect(latest.enabled).to be(true)
  end

  it 'blocks ties with a potentially overlapping enabled native rule' do
    JrcServiceDesk::PublishOperationalRulesService.new(user_context: sd_context).call(unit_id: sd_unit.id, kind: 'routing',
      definition: { 'rules' => [{ 'key' => 'legacy', 'precedence' => 10, 'match' => {}, 'output' => { 'queue_id' => queue.id } }] },
      enabled: true, expected_version: 0)
    attributes['enabled'] = true
    expect { preview }.to raise_error(JrcServiceDesk::IdempotencyConflict)
  end
end
