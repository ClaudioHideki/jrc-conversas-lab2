require 'rails_helper'

RSpec.describe JrcRelationship::PlaybookFlow do
  include_context 'JRC Service Desk domain'

  let(:context) { JrcRelationship::Context.new(sd_account_user) }
  let(:adapter) { described_class.new(context) }
  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'Synthetic CS11 pilot') }
  let(:assignment) { JrcRelationship::Assignment.create!(account: sd_account, contact: sd_contact, owner: sd_user) }
  let(:inbox) { create(:channel_api, account: sd_account).inbox }
  let(:conversation) { create(:conversation, account: sd_account, contact: sd_contact, inbox: inbox) }
  let(:source_key) { 'reviewed-cs11-source-1' }
  let(:graph) do
    nodes = [['start', {}], ['variable', { 'variable' => 'reviewed', 'value' => 'yes' }],
             ['note', { 'text' => 'Private reviewed customer note {{contact.name}}' }], ['end', {}]]
    {
      'nodes' => nodes.map.with_index do |(type, data), index|
        { 'id' => "node#{index}", 'type' => type, 'label' => "Native #{type}", 'position' => { 'x' => index * 100, 'y' => 0 }, 'data' => data }
      end,
      'edges' => (0..2).map do |index|
        { 'id' => "edge#{index}", 'source' => "node#{index}", 'target' => "node#{index + 1}", 'port' => 'next' }
      end
    }
  end
  let(:flow) do
    JrcFlow.create!(account: sd_account, created_by: sd_user, name: 'Pinned native internal playbook', kind: 'workflow',
                    status: 'active', graph: graph, settings: { 'trigger' => 'manual', 'inbox_ids' => [inbox.id], 'days' => [1, 2, 3, 4, 5] })
  end
  let(:step) do
    { 'kind' => 'flow', 'title' => 'Explicit native review', 'after_days' => 0, 'step_key' => 'native_review',
      'flow_id' => flow.id, 'flow_lock_version' => flow.lock_version, 'flow_digest' => described_class.definition_digest(flow),
      'contact_id' => sd_contact.id, 'conversation_id' => conversation.id, 'business_unit_id' => assignment.business_unit_id }
  end
  let(:book) do
    JrcRelationship::Playbook.create!(account: sd_account, name: 'Published CS11 origin', active: true, trigger_kind: 'health', steps: [step])
  end
  let(:version) { book.versions.create!(account: sd_account, actor: sd_user, version: book.version, payload: book.snapshot) }

  around do |example|
    with_modified_env(JRC_FLOWS_ENABLED: 'true', JRC_FLOWS_EXTERNAL_BETA: 'false') { example.run }
  end

  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm', 'jrc_flows')
    sd_contact.update!(email: 'cs11-private-contact@example.com', company_id: company.id)
  end

  def preview(value = step, origin = source_key)
    version
    adapter.preview(assignment: assignment, step: value, source_key: origin, playbook: book)
  end

  def execute(value = step, origin = source_key, digest: nil)
    review = preview(value, origin)
    execution = JrcRelationship::PlaybookExecution.create_or_find_by!(account: sd_account, execution_key: Digest::SHA256.hexdigest(origin)) do |row|
      row.assign_attributes(assignment: assignment, playbook: book, actor: sd_user, version: book.version, source_key: origin,
                            snapshot: book.snapshot, step_source_keys: [origin])
    end
    adapter.call(assignment: assignment, step: value, source_key: origin, payload_digest: digest || review.fetch('payload_digest'),
                 execution: execution, approval_token: review['approval_token'])
  end

  def enable_effects!
    policy = JrcRelationship::PlaybookFlowPolicy::DEFAULTS.deep_dup.merge('approved_phase' => 1, 'pilot_company_ids' => [company.id],
                                                                          'pilot_account_user_ids' => [sd_account_user.id],
                                                                          'allow_unassigned_business_unit' => true)
    JrcRelationship::Configuration.create!(account: sd_account, rules: { 'playbook_flow_effects_enabled' => true, 'playbook_flow_policy' => policy })
  end

  it 'uses the native simulator without writing runs, messages or actions and without exposing its content' do
    step
    before = [JrcFlowRun.count, Message.count, JrcRelationship::Action.count]
    data = preview
    expect(data).to include('state' => 'preview', 'status' => 'completed', 'reason' => 'playbook_flow_effects_disabled')
    expect(data.fetch('simulation').fetch('trace')).to all(include('simulated' => true))
    expect(data.to_json).not_to include('Private reviewed customer note', sd_contact.email.to_s, 'variables', 'content', 'graph')
    expect([JrcFlowRun.count, Message.count, JrcRelationship::Action.count]).to eq(before)
  end

  it 'keeps all effects disabled by default without claiming a run or completion' do
    data = execute
    expect(data).to include('state' => 'blocked', 'reason' => 'playbook_flow_effects_disabled')
    expect(data).not_to have_key('flow_run_id')
    expect(JrcFlowRun.where(flow: flow)).not_to exist
  end

  it 'executes a real native run once, with a private note and a persisted origin/version/payload stamp' do
    enable_effects!
    first = execute
    expect(first).to include('state' => 'completed', 'status' => 'completed', 'replayed' => false)
    run = JrcFlowRun.find(first.fetch('flow_run_id'))
    expect(run).to have_attributes(variables: include('reviewed' => 'yes'),
                                   settings: include('_flow_version' => flow.lock_version,
                                                     '_relationship_playbook' => include('assignment_id' => assignment.id,
                                                                                         'source_key' => source_key)))
    notes = conversation.messages.reload.select { |message| message.content_attributes['jrc_flow_run_id'] == run.id }
    expect(notes.size).to eq(1)
    note = notes.fetch(0)
    expect(note).to be_persisted.and(be_private).and(have_attributes(content: include('Private reviewed customer note')))
    expect { expect(execute).to include('flow_run_id' => run.id, 'replayed' => true, 'state' => 'completed') }
      .not_to(change { [JrcFlowRun.count, conversation.messages.count] })
    expect(first.to_json).not_to include('variables', 'Private reviewed customer note', sd_contact.email.to_s)
  end

  it 'binds the reviewed step and native publication even if graph columns change without lock_version' do
    enable_effects!
    digest = preview.fetch('payload_digest')
    changed = step.merge('title' => 'Different reviewed title')
    expect { execute(changed, digest: digest) }.to raise_error(ArgumentError, /payload changed/)
    changed_graph = graph.deep_dup.tap { |value| value['nodes'][2]['data']['text'] = 'Changed graph' }
    attributes = [ActiveRecord::Relation::QueryAttribute.new('graph', changed_graph, JrcFlow.type_for_attribute('graph')),
                  ActiveRecord::Relation::QueryAttribute.new('id', flow.id, JrcFlow.type_for_attribute('id'))]
    JrcFlow.connection.exec_update('UPDATE jrc_flows SET graph = $1::jsonb WHERE id = $2', 'Simulated graph corruption', attributes)
    expect { execute(digest: digest) }.to raise_error(ArgumentError, /version changed/)
    expect(JrcFlowRun.where(flow: flow)).not_to exist
  end

  it 'rejects a changed flow pin and a paused publication before any run is written' do
    changed = step.merge('flow_lock_version' => flow.lock_version + 1)
    expect { preview(changed) }.to raise_error(ArgumentError, /version changed/)
    step
    flow.update!(status: 'paused')
    expect { preview }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'revalidates a revoked initiator from the previously created context' do
    enable_effects!
    digest = preview.fetch('payload_digest')
    sd_account_user.update!(role: :agent)
    expect { execute(digest: digest) }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcFlowRun.where(flow: flow)).not_to exist
    expect(described_class.catalog(context)).to eq([])
  end

  it 'revalidates the explicit publisher rather than substituting another administrator' do
    publisher = create(:user, account: sd_account, role: :administrator)
    flow.update!(created_by: publisher)
    step
    enable_effects!
    digest = preview.fetch('payload_digest')
    sd_account.account_users.find_by!(user: publisher).update!(role: :agent)
    expect { execute(digest: digest) }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcFlowRun.where(flow: flow)).not_to exist
  end

  it 'rejects foreign and unrelated contacts/conversations without inferring a customer' do
    other_contact = create(:contact, account: sd_account)
    other = create(:conversation, account: sd_account, contact: other_contact, inbox: inbox)
    expect { preview(step.merge('contact_id' => other_contact.id, 'conversation_id' => other.id)) }
      .to raise_error(ActiveRecord::RecordNotFound)
    foreign = create(:conversation, account: sd_foreign_account)
    expect { preview(step.merge('conversation_id' => foreign.id)) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { preview(step.merge('contact_id' => sd_foreign_account.contacts.create!(name: 'Foreign').id)) }
      .to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'binds explicit CRM BusinessUnit identity and rejects changed/inactive assignments' do
    unit = JrcCrm::BusinessUnit.create!(account: sd_account, code: 'CS11UNIT', name: 'Explicit CRM Unit')
    assignment.update!(business_unit: unit)
    step
    expect(preview.fetch('scope')['business_unit_id']).to eq(unit.id)
    expect { preview(step.merge('business_unit_id' => nil)) }.to raise_error(Pundit::NotAuthorizedError)
    unit.update!(active: false)
    expect { preview }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'rejects altered inbox scope and native contact binding' do
    digest = preview.fetch('payload_digest')
    other_inbox = create(:channel_api, account: sd_account).inbox
    flow.update!(settings: flow.settings.merge('inbox_ids' => [other_inbox.id]))
    expect { execute(digest: digest) }.to raise_error(ArgumentError, /version changed/)
    other_contact = create(:contact, account: sd_account)
    conversation.contact_inbox.update!(contact: other_contact)
    expect { preview(step.merge('flow_lock_version' => flow.reload.lock_version, 'flow_digest' => described_class.definition_digest(flow))) }
      .to raise_error(Pundit::NotAuthorizedError)
  end

  it 'blocks client effects not approved by policy and changed continuations without a published origin, preserving preview' do
    enable_effects!
    { 'message' => { 'text' => 'No external send' }, 'delay' => { 'seconds' => 5 } }.each do |type, data|
      changed_graph = graph.deep_dup
      changed_graph['nodes'][2].merge!('type' => type, 'data' => data)
      flow.update!(graph: changed_graph)
      value = step.merge('flow_lock_version' => flow.lock_version, 'flow_digest' => described_class.definition_digest(flow))
      data = preview(value)
      expect(data.fetch('simulation').fetch('status')).to eq('completed')
      if type == 'message'
        result = execute(value, "blocked-#{type}")
        expect(result).to include('state' => 'blocked', 'reason' => 'playbook_flow_effect_not_approved:message')
      else
        expect { execute(value, "blocked-#{type}") }.to raise_error(ArgumentError, /step_not_published/)
      end
    end
    expect(JrcFlowRun.where(flow: flow)).not_to exist
    expect(conversation.messages).not_to exist
  end

  it 'does not resume an unrelated live run for the selected conversation' do
    enable_effects!
    run = flow.runs.create!(account: sd_account, conversation: conversation, event_key: 'native-unrelated-origin',
                            graph: graph, settings: flow.settings.merge('_flow_version' => flow.lock_version), node_id: 'node0')
    expect(execute).to include('state' => 'blocked', 'reason' => 'native_conversation_live_run_exists')
    expect(run.reload.steps).to eq(0)
    expect(conversation.messages).not_to exist
  end

  it 'reports a real native pause when a human took over and never claims completion' do
    enable_effects!
    conversation.update!(assignee: sd_user)
    value = execute
    expect(value).to include('state' => 'paused', 'status' => 'paused', 'reason' => 'native_run_requires_review')
    expect(JrcFlowRun.find(value.fetch('flow_run_id')).status).to eq('paused')
    expect(conversation.messages).not_to exist
  end

  it 'refuses a replay with a modified payload at the same native origin' do
    enable_effects!
    original = execute
    expect { execute(step.merge('title' => 'Reused origin with different content')) }.to raise_error(ArgumentError, /step_not_published/)
    expect(JrcFlowRun.where(flow: flow).pluck(:id)).to eq([original.fetch('flow_run_id')])
    expect(conversation.messages.count).to eq(1)
  end

  it 'binds actual native contact values to the reviewed hash without exposing them in the preview' do
    enable_effects!
    digest = preview.fetch('payload_digest')
    sd_contact.update!(name: 'Changed contact identity')
    expect { execute(digest: digest) }.to raise_error(ArgumentError, /payload changed/)
    expect(JrcFlowRun.where(flow: flow)).not_to exist
  end

  it 'never retries an uncertain persisted native run or a tampered scope on replay' do
    enable_effects!
    run = JrcFlowRun.find(execute.fetch('flow_run_id'))
    run.update!(status: 'running', finished_at: nil)
    expect { expect(execute).to include('state' => 'running', 'replayed' => true, 'reason' => 'native_run_requires_review') }
      .not_to(change { conversation.messages.count })
    foreign_contact = create(:contact, account: sd_foreign_account)
    run.update!(settings: run.settings.deep_dup.tap { |settings| settings['_relationship_playbook']['contact_id'] = foreign_contact.id })
    expect { execute }.to raise_error(ArgumentError, /origin was reused/)
  end

  it 'filters history using current native account/customer/actor/unit scope before pagination and revalidates pins' do
    enable_effects!
    run_id = execute.fetch('flow_run_id')
    expect(described_class.visible_runs(context: context, assignment: assignment).pluck(:id)).to eq([run_id])
    expect(described_class.visible_run?(context: context, assignment: assignment, id: run_id)).to be(true)
    flow.update!(graph: graph.deep_dup.tap { |value| value['nodes'][2]['data']['text'] = 'New publication' })
    expect(described_class.visible_run?(context: context, assignment: assignment, id: run_id)).to be(false)
    sd_account_user.update!(role: :agent)
    expect(described_class.visible_runs(context: context, assignment: assignment)).not_to exist
  end

  it 'never exposes graph/credentials in the published choices and excludes foreign/draft/non-admin flows' do
    flow.connection_secrets = { 'http_api_key' => 'synthetic-cs11-secret-for-test' }
    flow.save!
    data = described_class.catalog(context)
    expect(data.pluck('id')).to eq([flow.id])
    expect(data.first).to include('flow_lock_version' => flow.lock_version, 'flow_digest' => described_class.definition_digest(flow))
    expect(data.to_json).not_to include('synthetic-cs11-secret-for-test', 'graph', 'credential', 'source_definition')
  end

  it 'requires bounded explicit source and step identifiers and immediate timing' do
    expect { preview(step, '') }.to raise_error(ArgumentError)
    expect { preview(step.merge('step_key' => nil)) }.to raise_error(ArgumentError)
    expect { preview(step.merge('after_days' => 1)) }.to raise_error(ArgumentError)
    expect { preview(step.merge('flow_id' => flow.id.to_s)) }.to raise_error(ArgumentError)
    expect(JrcFlowRun.where(flow: flow)).not_to exist
  end

  it 'rechecks configuration after preview and keeps the native installation/account switches authoritative' do
    config = enable_effects!
    digest = preview.fetch('payload_digest')
    config.update!(rules: { 'playbook_flow_effects_enabled' => false }, version: config.version + 1)
    expect { execute(digest: digest) }.to raise_error(ArgumentError, /payload changed/)
    expect(execute).to include('state' => 'blocked', 'reason' => 'playbook_flow_effects_disabled')
    with_modified_env(JRC_FLOWS_ENABLED: 'false') do
      expect { preview }.to raise_error(Pundit::NotAuthorizedError)
      expect(described_class.catalog(context)).to eq([])
    end
    sd_account.disable_features!('jrc_flows')
    expect { preview }.to raise_error(Pundit::NotAuthorizedError)
  end
end
