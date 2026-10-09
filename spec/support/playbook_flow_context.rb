RSpec.shared_context 'with a published relationship Flow' do
  include_context 'JRC Service Desk domain'

  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'Synthetic continuation pilot') }
  let(:assignment) { JrcRelationship::Assignment.create!(account: sd_account, contact: sd_contact, owner: sd_user) }
  let(:inbox) { create(:channel_api, account: sd_account).inbox }
  let(:conversation) { create(:conversation, account: sd_account, contact: sd_contact, inbox: inbox) }
  let(:source_key) { 'published-continuation-source' }
  let(:node_definitions) do
    [['start', {}], ['delay', { 'seconds' => 5 }], ['input', { 'variable' => 'reply', 'timeout' => 30 }],
     ['note', { 'text' => 'Reviewed response {{reply}}' }], ['end', {}]]
  end
  let(:flow) do
    JrcFlow.create!(account: sd_account, created_by: sd_user, name: 'Published continuation fixture', kind: 'workflow', status: 'active',
                    graph: graph, settings: { 'trigger' => 'manual', 'inbox_ids' => [inbox.id], 'days' => [1, 2, 3, 4, 5] })
  end
  let(:step) do
    { 'kind' => 'flow', 'title' => 'Pinned continuation', 'after_days' => 0, 'step_key' => 'continuation',
      'flow_id' => flow.id, 'flow_lock_version' => flow.lock_version, 'flow_digest' => JrcRelationship::PlaybookFlow.definition_digest(flow),
      'contact_id' => sd_contact.id, 'conversation_id' => conversation.id, 'business_unit_id' => assignment.business_unit_id }
  end
  let(:book) do
    JrcRelationship::Playbook.create!(account: sd_account, name: 'Published continuation origin', active: true, trigger_kind: 'health', steps: [step])
  end
  let(:version) { book.versions.create!(account: sd_account, actor: sd_user, version: book.version, payload: book.snapshot) }
  let(:policy) do
    JrcRelationship::PlaybookFlowPolicy::DEFAULTS.deep_dup.merge('approved_phase' => 1, 'pilot_company_ids' => [company.id],
                                                                 'pilot_account_user_ids' => [sd_account_user.id],
                                                                 'allow_unassigned_business_unit' => true, 'allowed_effects' => %w[note message])
  end
  let(:configuration) do
    JrcRelationship::Configuration.create!(account: sd_account, rules: { 'playbook_flow_effects_enabled' => true, 'playbook_flow_policy' => policy })
  end
  let(:review) do
    version
    configuration
    adapter.preview(assignment: assignment, step: step, source_key: source_key, playbook: book)
  end
  let(:execution) do
    review
    JrcRelationship::PlaybookExecution.create!(account: sd_account, assignment: assignment, playbook: book, actor: sd_user, version: book.version,
                                               source_key: source_key, execution_key: Digest::SHA256.hexdigest(source_key),
                                               step_source_keys: [source_key],
                                               snapshot: book.snapshot.merge('results' => [{ 'step_key' => source_key, 'state' => 'pending' }]))
  end

  around do |example|
    with_modified_env(JRC_FLOWS_ENABLED: 'true', JRC_FLOWS_EXTERNAL_BETA: 'false') { example.run }
  end

  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm', 'jrc_flows')
    sd_contact.update!(company_id: company.id)
  end

  def context
    JrcRelationship::Context.new(sd_account_user)
  end

  def adapter
    JrcRelationship::PlaybookFlow.new(context)
  end

  def graph
    continuation_graph(node_definitions)
  end

  def tamper_flow_graph(value)
    attributes = [ActiveRecord::Relation::QueryAttribute.new('graph', value, JrcFlow.type_for_attribute('graph')),
                  ActiveRecord::Relation::QueryAttribute.new('id', flow.id, JrcFlow.type_for_attribute('id'))]
    JrcFlow.connection.exec_update('UPDATE jrc_flows SET graph = $1::jsonb WHERE id = $2', 'Simulated graph corruption', attributes)
  end

  def continuation_graph(definitions)
    nodes = definitions.map.with_index do |(type, data), index|
      { 'id' => "node#{index}", 'type' => type, 'label' => "Native #{type}", 'position' => { 'x' => index * 100, 'y' => 0 }, 'data' => data }
    end
    edges = (0...(nodes.length - 1)).map do |index|
      { 'id' => "edge#{index}", 'source' => "node#{index}", 'target' => "node#{index + 1}", 'port' => 'next' }
    end
    nodes.select { |node| node['type'] == 'input' }.each do |node|
      edges << { 'id' => "timeout#{node['id']}", 'source' => node['id'], 'target' => nodes.last['id'], 'port' => 'timeout' }
    end
    { 'nodes' => nodes, 'edges' => edges }
  end

  def start_continuation(token: review['approval_token'], digest: review.fetch('payload_digest'), origin: execution)
    result = adapter.call(assignment: assignment, step: step, source_key: source_key, payload_digest: digest,
                          execution: origin, approval_token: token)
    result['flow_run_id'] ? JrcFlowRun.find(result.fetch('flow_run_id')) : result
  end

  def wake_continuation(run)
    travel_to(run.reload.wake_at, with_usec: true) { JrcRelationship::PlaybookFlowResumeJob.perform_now(run.id, run.wake_version) }
    run.reload
  end

  def client_reply(content: 'explicit client response', contact: sd_contact)
    create(:message, account: sd_account, conversation: conversation, inbox: inbox, sender: contact, message_type: :incoming, content: content)
  end

  def flow_messages(run)
    conversation.messages.reload.select { |message| message.content_attributes['jrc_flow_run_id'] == run.id }
  end
end
