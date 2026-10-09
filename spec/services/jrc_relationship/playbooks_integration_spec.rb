require 'rails_helper'

RSpec.describe JrcRelationship::Playbooks do
  include_context 'with a published relationship Flow'
  let(:node_definitions) { [['start', {}], ['note', { 'text' => 'Approved internal note' }], ['end', {}]] }

  def full_source(key)
    "playbook:#{book.id}:v#{book.version}:#{step.fetch('step_key')}:#{key}"
  end

  it 'keeps an OFF execution immutable and does not turn a retry into a newly approved run' do
    version
    configuration.update!(rules: configuration.rules.merge('playbook_flow_effects_enabled' => false))
    service = described_class.new(context)
    service.run!(assignment, 'health', playbook_id: book.id, source_key: 'first-reviewed-source')
    first = JrcRelationship::PlaybookExecution.find_by!(playbook: book)
    expect(first.snapshot['results'].first).to include('state' => 'blocked', 'reason' => 'playbook_flow_effects_disabled')
    expect(JrcFlowRun).not_to exist
    configuration.update!(rules: configuration.rules.merge('playbook_flow_effects_enabled' => true))
    service.run!(assignment, 'health', playbook_id: book.id, source_key: 'first-reviewed-source')
    expect(JrcFlowRun).not_to exist
    expect(first.reload.snapshot['results'].first['state']).to eq('blocked')
  end

  it 'persists the original execution before effects and projects a real approved run without mutating its snapshot' do
    version
    configuration
    key = 'second-reviewed-source'
    origin = full_source(key)
    review = adapter.preview(assignment: assignment, step: step, source_key: origin, playbook: book)
    options = { playbook_id: book.id, source_key: key, flow_approvals: { origin => review.fetch('approval_token') } }
    2.times { described_class.new(context).run!(assignment, 'health', **options) }
    expect(JrcFlowRun.where(flow: flow).count).to eq(1)
    record = JrcRelationship::PlaybookExecution.find_by!(playbook: book, source_key: key)
    expect(record.snapshot['results'].first).to include('state' => 'pending')
    expect(record.snapshot.to_json).not_to include(review.fetch('approval_token'))
    expect(adapter.projection(execution: record).first).to include('state' => 'completed', 'resource_type' => 'JrcFlowRun',
                                                                   'resource_id' => flow.runs.first.id)
    customer = assignment.customer_context(sd_account_user)
    expect(customer.timeline_sources.fetch('relationship_playbook_execution').first).to include(record)
    expect(record.reload.snapshot['results'].first['state']).to eq('pending')
  end

  it 'rejects an absent step key, a delayed step and a foreign flow reference before publication' do
    [step.except('step_key'), step.merge('after_days' => 1),
     step.merge('contact_id' => create(:contact, account: sd_foreign_account).id)].each do |invalid|
      candidate = JrcRelationship::Playbook.new(account: sd_account, name: 'Invalid flow book', trigger_kind: 'health', steps: [invalid])
      expect(candidate).not_to be_valid
    end
    expect(JrcFlowRun).not_to exist
    expect(JrcRelationship::PlaybookExecution).not_to exist
  end
end
