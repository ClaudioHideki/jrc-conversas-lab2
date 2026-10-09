require 'rails_helper'

RSpec.describe JrcRelationship::PlaybookNativeResult do
  include_context 'with a published relationship Flow'
  let(:assignment) { JrcRelationship::Assignment.create!(account: sd_account, company: company, owner: sd_user) }
  let(:node_definitions) { [['start', {}], ['note', { 'text' => 'Approved mixed book' }], ['end', {}]] }
  let(:native_step) { { 'kind' => 'activity', 'title' => 'Native reviewed follow-up', 'after_days' => 0, 'step_key' => 'follow_up' } }
  let(:book) do
    JrcRelationship::Playbook.create!(
      account: sd_account, name: 'Published mixed book', active: true, trigger_kind: 'health', steps: [step, native_step]
    )
  end
  let(:flow_source) { "playbook:#{book.id}:v#{book.version}:#{step.fetch('step_key')}:#{source_key}" }
  let(:native_source) { "playbook:#{book.id}:v#{book.version}:#{native_step.fetch('step_key')}:#{source_key}" }
  let(:execution) { JrcRelationship::PlaybookExecution.find_by!(playbook: book, assignment: assignment, source_key: source_key) }
  let(:native_action) { assignment.actions.find_by!(source_key: "activity:#{native_source}") }

  before do
    version
    configuration
    review = adapter.preview(assignment: assignment, step: step, source_key: flow_source, playbook: book)
    options = { playbook_id: book.id, source_key: source_key, flow_approvals: { flow_source => review.fetch('approval_token') } }
    2.times { JrcRelationship::Playbooks.new(context).run!(assignment, 'health', **options) }
  end

  def native_projection
    adapter.projection(execution: execution).find { |row| row['step_key'] == native_source }
  end

  def tamper_activity_binding(activity)
    metadata = activity.metadata.merge('relationship_assignment_id' => assignment.id + 1)
    attributes = [ActiveRecord::Relation::QueryAttribute.new('metadata', metadata, JrcCrm::Activity.type_for_attribute('metadata')),
                  ActiveRecord::Relation::QueryAttribute.new('id', activity.id, JrcCrm::Activity.type_for_attribute('id'))]
    JrcCrm::Activity.connection.exec_update(
      'UPDATE jrc_crm_activities SET metadata = $1::jsonb WHERE id = $2', 'Simulated binding corruption', attributes
    )
  end

  it 'projects the actual native Action and Activity after replay without changing the original execution' do
    original = execution.snapshot.deep_dup
    expect(native_projection).to include('state' => 'planned', 'reason' => nil, 'resource_type' => 'JrcRelationship::Action',
                                         'resource_id' => native_action.id, 'activity_id' => native_action.activity_id)
    expect(native_action.activity).to have_attributes(account_id: sd_account.id, company_id: company.id, contact_id: nil,
                                                      business_unit_id: assignment.business_unit_id, title: native_step['title'])
    expect([JrcFlowRun.where(flow: flow).count, assignment.actions.count, sd_account.jrc_crm_activities.count]).to eq([1, 1, 1])
    expect(execution.reload.snapshot).to eq(original)
  end

  it 'blocks the native projection when the current CRM grant is revoked and leaves its real resources intact' do
    original = execution.snapshot.deep_dup
    sd_account.disable_features!('jrc_crm')
    expect(native_projection).to include('state' => 'blocked', 'reason' => 'native_permission_unavailable')
    expect(native_projection.keys).not_to include('resource_id', 'activity_id')
    expect(execution.reload.snapshot).to eq(original)
    expect(native_action.activity.reload).to be_persisted
  end

  it 'rejects an altered Activity binding rather than exposing a different customer resource' do
    activity = native_action.activity
    tamper_activity_binding(activity)
    expect(native_projection).to include('state' => 'blocked', 'reason' => 'native_permission_unavailable')
    expect(native_projection.keys).not_to include('resource_id', 'activity_id')
    expect(execution.reload.snapshot['results'].last).to include('state' => 'pending', 'reason' => 'native_execution_pending')
  end

  it 'rejects an Execution from another Assignment before querying a native resource' do
    contact = create(:contact, account: sd_account)
    other = JrcRelationship::Assignment.create!(account: sd_account, contact: contact, owner: sd_user)
    projection = described_class.new(context: context, assignment: other)
    expect { projection.native_step?(execution: execution, result: execution.snapshot['results'].last) }.to raise_error(Pundit::NotAuthorizedError)
    expect(execution.reload.snapshot['results'].last).to include('state' => 'pending', 'reason' => 'native_execution_pending')
  end
end
