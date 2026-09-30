require 'rails_helper'

RSpec.describe 'NICO customer actions and notices', type: :request do
  let(:account) { create(:account, custom_attributes: { 'nico_enabled' => true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_nico/operations" }
  let(:conversation) { create(:conversation, account: account) }
  let(:notice) do
    JrcNico::Notice.publish!(account: account, user: admin, conversation: conversation,
      event_key: 'test-action', kind: 'action', request: 'Atualize meu email para marina@example.test', body: 'Cliente pediu atualização de cadastro')
  end

  it 'prepares a customer action without cancelling the operator task, then notifies its real result' do
    post "#{base}/prepare", params: { request_id: SecureRandom.uuid, message: 'Outro trabalho', tool: 'create_contact',
      arguments: { name: 'Outro cliente', email: 'outro@example.test' } }, headers: headers, as: :json
    other_id = response.parsed_body['commands'].first['id']
    allow(JrcNico::OperationalInference).to receive(:call) do |**args|
      expect(args[:history]).to be_empty
      expect(args[:context][:selected_conversation][:contact_id]).to eq(conversation.contact_id)
      { 'reply' => 'Atualizar o email deste cliente', 'tool' => 'update_contact',
        'arguments' => { 'contact_id' => conversation.contact_id, 'email' => 'marina@example.test' } }
    end
    expect { JrcNico::NoticePlanJob.perform_now(notice.id) }.not_to change { conversation.contact.reload.email }
    command = notice.commands.last
    expect(command.status).to eq('awaiting_confirmation')
    expect(JrcNico::Command.find(other_id).status).to eq('awaiting_confirmation')
    post "#{base}/commands/#{command.id}/confirm", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(conversation.contact.reload.email).to eq('marina@example.test')
    expect(notice.reload.status).to eq('succeeded')
    expect(notice.read_at).to be_nil
    expect { post "#{base}/commands/#{command.id}/confirm", headers: headers, as: :json }.not_to change { conversation.contact.reload.updated_at }
  end

  it 'does not prepare an action on another customer, even in the same account' do
    other = create(:contact, account: account, name: 'Outro cliente')
    allow(JrcNico::OperationalInference).to receive(:call).and_return(
      'reply' => 'Trocar dados', 'tool' => 'update_contact', 'arguments' => { 'contact_id' => other.id, 'name' => 'Não alterar' })
    JrcNico::NoticePlanJob.perform_now(notice.id)
    expect(notice.commands.last.status).to eq('failed')
    expect(other.reload.name).to eq('Outro cliente')
  end

  it 'retains customer previews when the operator sends another unrelated request' do
    command = JrcNico::OperatorSession.new(account: account, user: admin).session.commands.create!(
      source_notice: notice, request_id: SecureRandom.uuid, message: notice.request, status: 'awaiting_confirmation',
      tool: 'update_contact', arguments: { contact_id: conversation.contact_id, email: 'new@example.test' })
    post "#{base}/prepare", params: { request_id: SecureRandom.uuid, message: 'Outra tarefa', tool: 'create_contact',
      arguments: { name: 'Outro', email: 'outro@example.test' } }, headers: headers, as: :json
    expect(command.reload.status).to eq('awaiting_confirmation')
  end

  it 'shows persistent notifications only to their owner and supports marking them read' do
    notice
    get "#{base}/notices", headers: headers
    expect(response.parsed_body['unread_count']).to eq(1)
    expect(response.parsed_body['notices'].first['conversation_id']).to eq(conversation.display_id)
    other = create(:user, account: account, role: :administrator)
    get "#{base}/notices", headers: other.create_new_auth_token
    expect(response.parsed_body['notices']).to be_empty
    post "#{base}/notices/#{notice.id}/read", headers: other.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post "#{base}/notices/#{notice.id}/read", headers: headers, as: :json
    expect(response.parsed_body['unread_count']).to eq(0)
  end

  it 'revalidates conversation access before approving a queued customer action' do
    command = JrcNico::OperatorSession.new(account: account, user: admin).session.commands.create!(
      source_notice: notice, request_id: SecureRandom.uuid, message: notice.request, status: 'awaiting_confirmation',
      tool: 'update_contact', arguments: { contact_id: conversation.contact_id, email: 'new@example.test' })
    account.update!(custom_attributes: { 'nico_enabled' => false })
    post "#{base}/commands/#{command.id}/confirm", headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(conversation.contact.reload.email).not_to eq('new@example.test')
  end

  it 'does not repeat a completed action while planning the next step' do
    operator = JrcNico::OperatorSession.new(account: account, user: admin)
    args = { 'contact_id' => conversation.contact_id, 'email' => 'new@example.test' }
    operator.session.commands.create!(source_notice: notice, request_id: SecureRandom.uuid, message: notice.request,
      status: 'succeeded', tool: 'update_contact', arguments: args, reply: 'Concluído')
    allow(JrcNico::OperationalInference).to receive(:call).and_return('tool' => 'update_contact', 'arguments' => args, 'reply' => 'Repetir')
    JrcNico::NoticePlanJob.perform_now(notice.id)
    expect(notice.commands.last.tool).to be_nil
    expect(notice.reload.status).to eq('review')
  end

  it 'removes greetings only on continuation replies and preserves the customer name and content' do
    expect(JrcNico::CustomerReply.normalize('Olá, Marina! Vamos continuar.', continuation: true)).to eq('Marina! Vamos continuar.')
    expect(JrcNico::CustomerReply.normalize('Bom dia! O agendamento precisa de um horário.', continuation: true)).to eq('O agendamento precisa de um horário.')
    expect(JrcNico::CustomerReply.normalize('Olá, sou o NICO.', continuation: false)).to eq('Olá, sou o NICO.')
    expect(JrcNico::CustomerReply.normalize('O produto se chama Olá.', continuation: true)).to eq('O produto se chama Olá.')
  end

  it 'omits optional nulls from model arguments without accepting unknown or required null fields' do
    account.enable_features!('jrc_crm')
    access = JrcNico::OperationalAccess.new(account: account, user: admin).authorize!
    catalog = JrcNico::ToolCatalog.new(access)
    args = { 'title' => 'Reunião', 'activity_type' => 'meeting', 'due_at' => '2026-09-11T15:00:00-03:00', 'lead_id' => nil, 'deal_id' => 1 }
    normalized = catalog.normalize_arguments('create_activity', args)
    expect(normalized).not_to have_key('lead_id')
    expect { catalog.validate!('create_activity', normalized) }.not_to raise_error
    expect { catalog.validate!('create_activity', catalog.normalize_arguments('create_activity', args.merge('title' => nil))) }.to raise_error(ArgumentError)
    expect { catalog.validate!('create_activity', catalog.normalize_arguments('create_activity', args.merge('unknown' => nil))) }.to raise_error(ArgumentError)
  end

  it 'lets the planner correct incomplete activity arguments using actual records before review' do
    account.enable_features!('jrc_crm')
    lead = account.jrc_crm_leads.create!(name: 'Cliente teste', contact: conversation.contact, owner: admin)
    args = { 'title' => 'Reunião', 'activity_type' => 'meeting', 'due_at' => 2.days.from_now.iso8601, 'lead_id' => nil }
    allow(JrcNico::OperationalInference).to receive(:call).and_return(
      { 'tool' => 'create_activity', 'arguments' => args, 'reply' => 'Agendar' },
      { 'tool' => 'list_leads', 'arguments' => { 'contact_id' => conversation.contact_id }, 'reply' => 'Localizar lead' },
      { 'tool' => 'create_activity', 'arguments' => args.merge('lead_id' => lead.id), 'reply' => 'Agendar no lead encontrado' })
    expect { JrcNico::NoticePlanJob.perform_now(notice.id) }.not_to change { account.jrc_crm_activities.count }
    command = notice.commands.last
    expect(command.status).to eq('awaiting_confirmation')
    expect(command.arguments['lead_id']).to eq(lead.id)
    post "#{base}/commands/#{command.id}/confirm", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(account.jrc_crm_activities.last.lead).to eq(lead)
  end

  it 'preserves the actionable error and allows only the owner to retry failed planning' do
    allow(JrcNico::OperationalInference).to receive(:call).and_raise(ArgumentError, 'Informe o horário da reunião.')
    JrcNico::NoticePlanJob.perform_now(notice.id)
    expect(notice.reload.status).to eq('failed')
    expect(notice.body).to eq('Informe o horário da reunião.')
    other = create(:user, account: account, role: :administrator)
    post "#{base}/notices/#{notice.id}/retry", headers: other.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect { post "#{base}/notices/#{notice.id}/retry", headers: headers, as: :json }.to have_enqueued_job(JrcNico::NoticePlanJob).with(notice.id)
    expect(response).to have_http_status(:ok)
    expect(notice.reload.status).to eq('planning')
    expect { post "#{base}/notices/#{notice.id}/retry", headers: headers, as: :json }.not_to have_enqueued_job(JrcNico::NoticePlanJob)
  end

  it 'revalidates every source of a synthesized customer reply without replacing the operator selection' do
    account.enable_features!('jrc_crm')
    operator_user = create(:user, account: account, role: :agent)
    create(:inbox_member, inbox: conversation.inbox, user: operator_user)
    lead = create(:jrc_crm_lead, account: account, owner: operator_user, contact: conversation.contact, notes: 'REVOKED_NOTICE_SOURCE')
    operator = JrcNico::OperatorSession.new(account: account, user: operator_user)
    previous_selection = { 'tool' => 'count_contacts', 'result' => { 'count' => 7 } }
    operator.session.update!(context: operator.session.context.merge('last_result' => previous_selection))
    customer_notice = JrcNico::Notice.publish!(account: account, user: operator_user, conversation: conversation,
      event_key: 'read-source', kind: 'action', request: 'Consulte meu lead', body: 'Consulta do cliente')
    allow(JrcNico::OperationalInference).to receive(:call).and_return(
      { 'tool' => 'list_leads', 'arguments' => {}, 'reply' => 'Consultar lead' },
      { 'tool' => '', 'arguments' => {}, 'reply' => 'REVOKED_NOTICE_SOURCE' })
    JrcNico::NoticePlanJob.perform_now(customer_notice.id)
    command = customer_notice.commands.last
    expect(command.tool).to be_nil
    expect(command.result).to eq({})
    expect(command.execution_context['resources']).to include(['JrcCrm::Lead', lead.id])
    expect(operator.session.reload.context['last_result']).to eq(previous_selection)
    operator_headers = operator_user.create_new_auth_token
    get "#{base}/notices", headers: operator_headers
    expect(response.body).to include('REVOKED_NOTICE_SOURCE')

    lead.update!(owner: admin)
    get "#{base}/notices", headers: operator_headers
    expect(response.body).not_to include('REVOKED_NOTICE_SOURCE')
    get base, headers: operator_headers
    expect(response.body).not_to include('REVOKED_NOTICE_SOURCE')
    expect(response.parsed_body['commands']).to be_empty
    expect(response.parsed_body['messages']).to be_empty
  end

  it 'records mutation results from customer notices for later ownership revalidation' do
    account.enable_features!('jrc_crm')
    operator_user = create(:user, account: account, role: :agent)
    create(:inbox_member, inbox: conversation.inbox, user: operator_user)
    lead = create(:jrc_crm_lead, account: account, owner: operator_user, contact: conversation.contact, name: 'REVOKED_MUTATION_RESULT')
    operator = JrcNico::OperatorSession.new(account: account, user: operator_user)
    customer_notice = JrcNico::Notice.publish!(account: account, user: operator_user, conversation: conversation,
      event_key: 'write-source', kind: 'action', request: 'Qualifique o lead', body: 'Pedido do cliente')
    command = operator.session.commands.create!(source_notice: customer_notice, request_id: SecureRandom.uuid,
      message: customer_notice.request, status: 'awaiting_confirmation', tool: 'update_lead',
      arguments: { lead_id: lead.id, status: 'qualified' })
    operator.execute(command)
    expect(lead.reload.status).to eq('qualified')
    expect(command.reload.execution_context['resources']).to include(['JrcCrm::Lead', lead.id])
    expect(operator.session.reload.context['resources']).to include(['JrcCrm::Lead', lead.id])

    lead.update!(owner: admin)
    operator_headers = operator_user.create_new_auth_token
    get base, headers: operator_headers
    expect(response.body).not_to include('REVOKED_MUTATION_RESULT')
    expect(response.parsed_body['commands']).to be_empty
    get "#{base}/notices", headers: operator_headers
    expect(response.parsed_body['notices']).to be_empty
  end

  it 'hides a legacy synthesized notice whose source manifest cannot be reconstructed' do
    operator = JrcNico::OperatorSession.new(account: account, user: admin)
    operator.session.commands.create!(source_notice: notice, request_id: SecureRandom.uuid,
      message: notice.request, status: 'succeeded', reply: 'LEGACY_UNSCOPED_SUMMARY', tool: nil, result: {})
    get "#{base}/notices", headers: headers
    expect(response.body).not_to include('LEGACY_UNSCOPED_SUMMARY')
  end

  it 'revalidates an automation receipt against its Account and current record' do
    account.enable_features!('automations')
    rule = create(:automation_rule, account: account)
    foreign_rule = create(:automation_rule)
    access = JrcNico::OperationalAccess.new(account: account, user: admin).authorize!
    receipt = JrcNico::Notice.publish!(account: account, user: admin, event_key: 'automation-receipt', kind: 'result',
                                     body: 'Automation result', metadata: { tool: 'create_automation', resources: [['AutomationRule', rule.id]] })
    expect(receipt.visible_to?(access)).to be(true)

    receipt.update!(metadata: { tool: 'create_automation', resources: [['AutomationRule', foreign_rule.id]] })
    expect(receipt.visible_to?(access)).to be(false)
    receipt.update!(metadata: { tool: 'create_automation', resources: [['AutomationRule', rule.id]] })
    rule.destroy!
    expect(receipt.visible_to?(access)).to be(false)
  end

  it 'revalidates a campaign receipt against its Account and current record' do
    account.enable_features!('jrc_campaigns')
    campaign = account.jrc_campaigns.create!(name: 'Own campaign', created_by: admin)
    foreign_campaign = create(:account).jrc_campaigns.create!(name: 'Foreign campaign')
    access = JrcNico::OperationalAccess.new(account: account, user: admin).authorize!
    receipt = JrcNico::Notice.publish!(account: account, user: admin, event_key: 'campaign-receipt', kind: 'result',
                                     body: 'Campaign result', metadata: { tool: 'create_campaign', resources: [['JrcCampaigns::Campaign', campaign.id]] })
    expect(receipt.visible_to?(access)).to be(true)

    receipt.update!(metadata: { tool: 'create_campaign', resources: [['JrcCampaigns::Campaign', foreign_campaign.id]] })
    expect(receipt.visible_to?(access)).to be(false)
    receipt.update!(metadata: { tool: 'create_campaign', resources: [['JrcCampaigns::Campaign', campaign.id]] })
    campaign.destroy!
    expect(receipt.visible_to?(access)).to be(false)
  end

  it 'hides operator summaries after a listed campaign is removed' do
    account.enable_features!('jrc_campaigns')
    campaign = account.jrc_campaigns.create!(name: 'REMOVED_CAMPAIGN_SOURCE', created_by: admin)
    allow(JrcNico::OperationalInference).to receive(:call).and_return(
      { 'tool' => 'list_campaigns', 'arguments' => {}, 'reply' => 'Consultar campanhas' },
      { 'tool' => '', 'arguments' => {}, 'reply' => 'REMOVED_CAMPAIGN_SOURCE' })
    post "#{base}/ask", params: { request_id: SecureRandom.uuid, message: 'Consultar campanhas' }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('REMOVED_CAMPAIGN_SOURCE')

    campaign.destroy!
    get base, headers: headers
    expect(response.body).not_to include('REMOVED_CAMPAIGN_SOURCE')
    expect(response.parsed_body['commands']).to be_empty
  end

  it 'revokes synthesized catalog summaries even when the read returned no resource references' do
    account.enable_features!('jrc_crm')
    operator_user = create(:user, account: account, role: :agent)
    create(:inbox_member, inbox: conversation.inbox, user: operator_user)
    customer_notice = JrcNico::Notice.publish!(account: account, user: operator_user, conversation: conversation,
      event_key: 'catalog-source', kind: 'action', request: 'Consulte o catálogo', body: 'Consulta do cliente')
    allow(JrcNico::OperationalInference).to receive(:call).and_return(
      { 'tool' => 'list_products', 'arguments' => {}, 'reply' => 'Consultar catálogo' },
      { 'tool' => '', 'arguments' => {}, 'reply' => 'REVOKED_CATALOG_SUMMARY' })
    JrcNico::NoticePlanJob.perform_now(customer_notice.id)
    command = customer_notice.commands.last
    expect(command.execution_context['source_tools']).to include('list_products')
    expect(command.execution_context['resources']).to eq([])
    role = create(:custom_role, account: account, permissions: ['conversation_manage'])
    account.account_users.find_by!(user_id: operator_user.id).update!(custom_role: role)

    get "#{base}/notices", headers: operator_user.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('REVOKED_CATALOG_SUMMARY')
  end
end
