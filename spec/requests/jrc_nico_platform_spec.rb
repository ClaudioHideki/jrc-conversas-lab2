require 'rails_helper'

RSpec.describe 'NICO platform integration', type: :request do
  around { |example| perform_enqueued_jobs(only: JrcNico::PlanCommandJob) { example.run } }
  let(:account) { create(:account, custom_attributes: { 'nico_enabled' => true }) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:access) { JrcNico::OperationalAccess.new(account: account, user: user).authorize! }
  let(:executor) { JrcNico::ToolExecutor.new(access) }
  let(:inbox) { create(:inbox, account: account) }

  before { account.enable_features!('automations', 'jrc_crm') }

  it 'creates a persistent disabled rule and activates it separately' do
    result = executor.call('create_automation', 'name' => 'Resposta sobre produto', 'event_name' => 'message_created',
      'inbox_id' => inbox.id, 'content_contains' => 'produto', 'message_body' => 'Qual produto deseja conhecer?')
    rule = account.automation_rules.find(result[:record]['id'])
    expect(rule.active).to be(false)
    expect(rule.conditions).to include(hash_including('attribute_key' => 'message_type', 'values' => ['incoming']))
    expect(executor.call('list_automations', {}).map { |entry| entry['id'] }).to include(rule.id)
    executor.call('activate_automation', 'automation_id' => rule.id)
    expect(rule.reload.active).to be(true)
    executor.call('pause_automation', 'automation_id' => rule.id)
    expect(rule.reload.active).to be(false)
  end

  it 'cannot create a rule targeting another account inbox' do
    foreign_inbox = create(:inbox)
    expect do
      executor.call('create_automation', 'name' => 'Foreign', 'event_name' => 'message_created',
        'inbox_id' => foreign_inbox.id, 'content_contains' => 'produto', 'message_body' => 'Olá')
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(account.automation_rules.count).to eq(0)
  end

  it 'does not expose automation writes to an agent' do
    agent = create(:user, account: account, role: :agent)
    agent_access = JrcNico::OperationalAccess.new(account: account, user: agent).authorize!
    expect(JrcNico::ToolCatalog.new(agent_access).available.pluck(:name)).not_to include('create_automation', 'activate_automation')
  end

  it 'passes a recognized screen to the planner without accepting arbitrary context' do
    allow(JrcNico::OperationalInference).to receive(:call) do |**args|
      expect(args[:context][:current_module][:title]).to eq('Automações Inteligentes')
      { 'reply' => 'Configure evento, condições e ações.', 'tool' => '', 'arguments' => {} }
    end
    post "/api/v1/accounts/#{account.id}/jrc_nico/operations/ask", params: {
      message: 'O que faço nesta tela?', request_id: SecureRandom.uuid, route_name: 'automation_list'
    }, headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
  end

  it 'continues a compound request after a repeated read without executing the read twice' do
    allow(JrcNico::OperationalInference).to receive(:call).and_return(
      { 'reply' => '', 'tool' => 'count_contacts', 'arguments' => {} },
      { 'reply' => '', 'tool' => 'count_contacts', 'arguments' => {} },
      { 'reply' => 'Preciso do nome do novo contato.', 'tool' => '', 'arguments' => {} }
    )
    expect_any_instance_of(JrcNico::ToolExecutor).to receive(:count_contacts).once.and_return(count: 0)
    command = JrcNico::OperatorSession.new(account: account, user: user).ask(
      message: 'Conte os contatos e cadastre outro contato', request_id: SecureRandom.uuid)
    expect(command.reply).to eq('Preciso do nome do novo contato.')
    expect(JrcNico::OperationalInference).to have_received(:call).exactly(3).times
  end

  it 'rejects a CRM rule from another account before invoking the runner' do
    foreign = create(:account)
    rule = foreign.jrc_crm_automation_rules.create!(name: 'Foreign', trigger_type: 'deal_created', conditions: [], actions: [])
    expect(JrcCrm::AutomationRunnerService).not_to receive(:new)
    expect { JrcCrm::ExecuteAutomationJob.perform_now(rule.id, 'Deal', 1, account.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
