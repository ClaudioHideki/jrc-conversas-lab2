require 'rails_helper'

RSpec.describe 'NICO operational assistant', type: :request do
  let(:account) { create(:account, custom_attributes: { 'nico_enabled' => true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_nico/operations" }
  let(:request_id) { SecureRandom.uuid }
  let(:contact_input) { { request_id: request_id, message: 'Cadastre Maria', tool: 'create_contact', arguments: { name: 'Maria QA', phone_number: '+5511991234567' } } }
  let(:conversation) { create(:conversation, account: account) }

  it 'prepares a contact, persists the conversation and executes an approval exactly once' do
    expect { post "#{base}/prepare", params: contact_input, headers: headers, as: :json }.not_to change(Contact, :count)
    expect(response).to have_http_status(:ok)
    command = response.parsed_body.fetch('commands').first
    expect(command['status']).to eq('awaiting_confirmation')
    expect do
      post "#{base}/commands/#{command['id']}/confirm", headers: headers, as: :json
    end.to change(account.contacts, :count).by(1)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['commands'].first['status']).to eq('succeeded')
    expect do
      post "#{base}/commands/#{command['id']}/confirm", headers: headers, as: :json
    end.not_to change(Contact, :count)
    get base, headers: headers
    expect(response.parsed_body['messages'].first['content']).to eq('Cadastre Maria')
  end

  it 'rejects unauthorized parameters and does not allow model-controlled method dispatch' do
    post "#{base}/prepare", params: contact_input.merge(tool: 'send'), headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    post "#{base}/prepare", params: contact_input.merge(request_id: SecureRandom.uuid, arguments: { name: 'Maria', account_id: account.id }), headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'keeps incomplete requests in conversation without creating a resource' do
    allow(JrcNico::OperationalInference).to receive(:call).and_return('reply' => 'Qual é o nome do contato?', 'tool' => '', 'arguments' => {})
    expect do
      post "#{base}/ask", params: { request_id: request_id, message: 'Crie um contato' }, headers: headers, as: :json
    end.not_to change(Contact, :count)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['messages'].last['content']).to eq('Qual é o nome do contato?')
  end

  it 'does not show or execute CRM tools when the account CRM module is disabled' do
    account.disable_features!('jrc_crm')
    operator = create(:user, account: account, role: :agent)
    operator_headers = operator.create_new_auth_token
    post "#{base}/prepare", params: contact_input.merge(tool: 'create_lead', arguments: { name: 'Denied' }), headers: operator_headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(account.jrc_crm_leads).to be_empty
  end

  it 'applies native CustomRole CRM permissions to tools and execution' do
    account.enable_features!('jrc_crm')
    operator = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: ['conversation_manage'])
    account.account_users.find_by!(user_id: operator.id).update!(custom_role: role)
    operator_headers = operator.create_new_auth_token
    get base, headers: operator_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['tools'].map { |tool| tool['name'] }).not_to include('list_leads', 'create_lead', 'create_deal')

    expect do
      post "#{base}/prepare", params: { request_id: SecureRandom.uuid, message: 'Criar lead', tool: 'create_lead',
        arguments: { name: 'Sem autorização CRM' } }, headers: operator_headers, as: :json
    end.not_to change(JrcCrm::Lead, :count)
    expect(response).to have_http_status(:forbidden)
    access = JrcNico::OperationalAccess.new(account: account, user: operator).authorize!
    expect { JrcNico::ToolExecutor.new(access).call('list_leads', {}) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'cancels a CRM preview when native role permissions are revoked before confirmation' do
    account.enable_features!('jrc_crm')
    operator = create(:user, account: account, role: :agent)
    operator_headers = operator.create_new_auth_token
    post "#{base}/prepare", params: { request_id: SecureRandom.uuid, message: 'Criar lead', tool: 'create_lead',
      arguments: { name: 'Prévia antiga' } }, headers: operator_headers, as: :json
    command = response.parsed_body.fetch('commands').first
    role = create(:custom_role, account: account, permissions: ['conversation_manage'])
    account.account_users.find_by!(user_id: operator.id).update!(custom_role: role)
    expect do
      post "#{base}/commands/#{command['id']}/confirm", headers: operator_headers, as: :json
    end.not_to change(JrcCrm::Lead, :count)
    expect(JrcNico::Command.find(command['id']).status).to eq('cancelled')
  end

  it 'revalidates account scope on approval and never updates another account contact' do
    other = create(:contact, name: 'Other account')
    post "#{base}/prepare", params: contact_input.merge(tool: 'update_contact', arguments: { contact_id: other.id, name: 'Intrusion' }), headers: headers, as: :json
    command = response.parsed_body.fetch('commands').first
    post "#{base}/commands/#{command['id']}/confirm", headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(other.reload.name).to eq('Other account')
  end

  it 'detects contact duplicates across different commands' do
    create(:contact, account: account, phone_number: '+5511991234567')
    post "#{base}/prepare", params: contact_input, headers: headers, as: :json
    command = response.parsed_body.fetch('commands').first
    expect do
      post "#{base}/commands/#{command['id']}/confirm", headers: headers, as: :json
    end.not_to change(Contact, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'invalidates a previous preview when the user corrects the request' do
    post "#{base}/prepare", params: contact_input, headers: headers, as: :json
    old_id = response.parsed_body.fetch('commands').first['id']
    post "#{base}/prepare", params: contact_input.merge(request_id: SecureRandom.uuid, message: 'Corrija o nome', arguments: { name: 'Maria corrigida', email: 'maria@example.test' }), headers: headers, as: :json
    expect do
      post "#{base}/commands/#{old_id}/confirm", headers: headers, as: :json
    end.not_to change(Contact, :count)
    expect(JrcNico::Command.find(old_id).status).to eq('cancelled')
  end

  it 'reserves three parallel model slots and enforces the fourth and token budget' do
    account.update!(custom_attributes: account.custom_attributes.merge('nico_monthly_token_limit' => 1_000_000))
    with_modified_env NICO_MODE: 'provider' do
      3.times do
        reservation = account.with_lock { JrcNico::RunCapacity.reservation_for!(account) }
        JrcNico::Inference.create!(account: account, user: admin, reserved_tokens: reservation)
      end
      expect { account.with_lock { JrcNico::RunCapacity.reservation_for!(account) } }.to raise_error(JrcNico::RunCapacity::Exceeded)
    end
  end

  it 'creates separate delegated sessions and replies for three clients without mixing their context' do
    conversations = 3.times.map do |index|
      contact = create(:contact, account: account, name: "Cliente #{index}")
      record = create(:conversation, account: account, contact: contact)
      create(:message, conversation: record, account: account, message_type: :incoming, content: "Sou Cliente #{index}, quero comprar.")
      record
    end
    contexts = []
    allow(JrcNico::OperationalInference).to receive(:call) do |**args|
      contexts << args[:context]
      { 'mode' => 'provider', 'reply' => 'Olá, sou o assistente virtual. Quantas unidades você precisa?', 'summary' => args[:message], 'handoff' => false, 'create_lead' => false }
    end
    with_modified_env NICO_MODE: 'provider' do
      post "#{base}/prepare", params: { request_id: request_id, message: 'Atenda estes três clientes', tool: 'delegate_conversations',
        arguments: { conversation_ids: conversations.map(&:display_id), objective: 'Qualificar compra', hours: 2, allow_crm: false } }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      command = response.parsed_body.fetch('commands').first
      post "#{base}/commands/#{command['id']}/confirm", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(JrcNico::Delegation.where(account: account).active.count).to eq(3)
      JrcNico::Delegation.where(account: account).order(:id).each { |d| JrcNico::CustomerTurnJob.perform_now(d.id) }
    end
    expect(contexts.size).to eq(3)
    contexts.each_with_index do |context, index|
      text = context[:conversation].to_json
      expect(text).to include("Cliente #{index}")
      expect(text).not_to include("Cliente #{(index + 1) % 3}")
    end
    expect(JrcNico::Turn.where(status: 'queued').count).to eq(3)
    conversations.each { |c| expect(c.messages.outgoing.count).to eq(1) }
  end

  it 'discards a generated response when the operator takes over during generation' do
    create(:message, conversation: conversation, account: account, message_type: :incoming, content: 'Quero comprar')
    access = JrcNico::OperationalAccess.new(account: account, user: admin)
    with_modified_env NICO_MODE: 'provider' do
      JrcNico::DelegationService.new(access).start('conversation_ids' => [conversation.display_id], 'objective' => 'Qualificar')
    end
    delegation = JrcNico::Delegation.find_by!(conversation: conversation)
    allow(JrcNico::OperationalInference).to receive(:call) do
      JrcNico::DelegationService.stop(conversation, reason: 'human_takeover', user: admin)
      { 'mode' => 'provider', 'reply' => 'Resposta que deve ser descartada', 'summary' => '', 'handoff' => false, 'create_lead' => false }
    end
    expect { JrcNico::CustomerTurnJob.perform_now(delegation.id) }.not_to change { conversation.messages.outgoing.count }
    expect(delegation.reload.status).to eq('paused')
    expect(delegation.turns.last.status).to eq('cancelled')
  end

  it 'does not send a queued bot reply after a public human message' do
    bot = AgentBot.create!(account: account, name: 'NICO QA')
    delegation = JrcNico::Delegation.create!(account: account, user: admin, conversation: conversation, agent_bot: bot, objective: 'Qualificar', expires_at: 1.hour.from_now)
    conversation.update!(status: 'pending', assignee_agent_bot: bot)
    message = Messages::MessageBuilder.new(bot, conversation, content: 'Pendente', content_attributes: { nico_delegation: { id: delegation.id, version: delegation.version } }).perform
    Messages::MessageBuilder.new(admin, conversation, content: 'Assumi o atendimento').perform
    job = SendReplyJob.new
    expect(job).not_to receive(:deliver)
    job.perform(message.id)
    expect(message.reload.status).to eq('failed')
  end

  it 'keeps internal notes out of commercial customer context' do
    JrcNico::KnowledgeDocument.create!(account: account, author: admin, approved_by: admin, approved_at: Time.current,
                                       title: 'Uso interno', body: 'SEGREDO DO DOCUMENTO INTERNO')
    JrcNico::KnowledgeDocument.create!(account: account, author: admin, approved_by: admin, approved_at: Time.current, customer_visible: true,
                                       title: 'Uso público', body: 'INFORMAÇÃO COMERCIAL PÚBLICA')
    create(:message, conversation: conversation, account: account, private: true, content: 'SEGREDO INTERNO DO OPERADOR')
    create(:message, conversation: conversation, account: account, message_type: :incoming, content: 'Quero comprar')
    bot = AgentBot.create!(account: account, name: 'NICO QA')
    delegation = JrcNico::Delegation.create!(account: account, user: admin, conversation: conversation, agent_bot: bot, objective: 'Qualificar', expires_at: 1.hour.from_now)
    conversation.update!(status: 'pending', assignee_agent_bot: bot)
    allow(JrcNico::OperationalInference).to receive(:call) do |**args|
      expect(args[:context].to_json).not_to include('SEGREDO INTERNO DO OPERADOR')
      expect(args[:context].to_json).not_to include('SEGREDO DO DOCUMENTO INTERNO')
      expect(args[:context].to_json).to include('INFORMAÇÃO COMERCIAL PÚBLICA')
      { 'mode' => 'provider', 'reply' => 'Olá!', 'summary' => 'Cliente quer comprar', 'handoff' => false, 'create_lead' => false }
    end
    JrcNico::CustomerTurnJob.perform_now(delegation.id)
    expect(delegation.turns.last.status).to eq('queued')
    expect { JrcNico::CustomerTurnJob.perform_now(delegation.id) }.not_to change { conversation.messages.outgoing.count }
  end

  it 'does not query ERP without the reference permission and configuration gates' do
    expect(JrcNico::ErpClient).not_to receive(:new)
    context = JrcNico::ContextBuilder.new(account: account, user: admin, conversation: conversation).build('Resumo')
    expect(context[:erp]).to eq([])
  end
  it 'clears historical CRM content when a lead changes owner without a role change' do
    account.enable_features!('jrc_crm')
    operator = create(:user, account: account, role: :agent)
    account.account_users.find_by!(user_id: operator.id).update!(crm_enabled: true)
    lead = account.jrc_crm_leads.create!(name: 'Reservado', owner: operator)
    session = JrcNico::OperatorSession.new(account: account, user: operator)
    session.session.append('assistant', 'Reservado')
    session.session.update!(context: session.session.context.merge('resources' => [['JrcCrm::Lead', lead.id]]))
    lead.update!(owner: admin)
    get base, headers: operator.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['messages']).to be_empty
  end

  it 'claims a browser operation once and rechecks membership before claiming' do
    post "#{base}/prepare", params: { message: 'Fique ocupado', request_id: request_id, tool: 'set_availability', arguments: { availability: 'busy' } }, headers: headers, as: :json
    id = response.parsed_body['commands'].first['id']
    post "#{base}/commands/#{id}/confirm", headers: headers, as: :json
    expect(response.parsed_body['commands'].first['status']).to eq('browser_pending')
    post "#{base}/commands/#{id}/claim", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    post "#{base}/commands/#{id}/claim", headers: headers, as: :json
    expect(response).to have_http_status(:too_many_requests)
    post "#{base}/commands/#{id}/receipt", params: { status: 'succeeded', detail: 'Disponibilidade atualizada' }, headers: headers, as: :json
    expect(response.parsed_body['commands'].first['status']).to eq('succeeded')
  end

  it 'transcribes authorized audio with quota accounting but does not create a command' do
    client = instance_double(JrcNico::RuntimeClient)
    allow(JrcNico::RuntimeClient).to receive(:new).and_return(client)
    allow(client).to receive(:transcribe).and_return('text' => 'Crie um contato', 'mode' => 'provider', 'model' => 'test-audio',
      'usage' => { 'input_tokens' => 100, 'output_tokens' => 10, 'total_tokens' => 110 })
    file = Tempfile.new(['nico-voice-spec', '.webm'])
    begin
      file.write('synthetic-test-audio-data')
      file.flush
      upload = Rack::Test::UploadedFile.new(file.path, 'audio/webm')
      expect { post "#{base}/transcribe", params: { audio: upload }, headers: headers }.not_to change(JrcNico::Command, :count)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('text' => 'Crie um contato')
      expect(account.jrc_ai_usage_events.last.total_tokens).to eq(110)
      account.update!(custom_attributes: account.custom_attributes.merge('nico_monthly_run_limit' => 0))
      expect(client).not_to receive(:transcribe)
      post "#{base}/transcribe", params: { audio: upload }, headers: headers
      expect(response).to have_http_status(:too_many_requests)
    ensure
      file.close!
    end
  end

  it 'does not retry a customer delivery with uncertain channel outcome' do
    bot = AgentBot.create!(account: account, name: 'NICO QA')
    delegation = JrcNico::Delegation.create!(account: account, user: admin, conversation: conversation, agent_bot: bot, objective: 'Qualificar', expires_at: 1.hour.from_now)
    conversation.update!(status: 'pending', assignee_agent_bot: bot)
    incoming = create(:message, conversation: conversation, account: account, message_type: :incoming, content: 'Olá')
    turn = delegation.turns.create!(message_id: incoming.id, version: delegation.version, status: 'queued')
    outgoing = Messages::MessageBuilder.new(bot, conversation, content: 'Olá!', content_attributes: { nico_turn_id: turn.id, nico_delegation: { id: delegation.id, version: delegation.version } }).perform
    turn.update!(outgoing_message_id: outgoing.id)
    job = SendReplyJob.new
    expect(job).to receive(:deliver).once.and_raise(Timeout::Error)
    job.perform(outgoing.id)
    job.perform(outgoing.id)
    expect(delegation.reload.status).to eq('needs_human')
    expect(turn.reload.status).to eq('cancelled')
  end

  it 'hands definitive channel failures to the operator without retrying delivery' do
    bot = AgentBot.create!(account: account, name: 'NICO QA')
    delegation = JrcNico::Delegation.create!(account: account, user: admin, conversation: conversation, agent_bot: bot,
      objective: 'Qualificar', expires_at: 1.hour.from_now)
    conversation.update!(status: 'pending', assignee_agent_bot: bot)
    incoming = create(:message, conversation: conversation, account: account, message_type: :incoming, content: 'Olá')
    turn = delegation.turns.create!(message_id: incoming.id, version: delegation.version, status: 'queued')
    outgoing = Messages::MessageBuilder.new(bot, conversation, content: 'Olá!', content_attributes: {
      nico_turn_id: turn.id, nico_delegation: { id: delegation.id, version: delegation.version }
    }).perform
    turn.update!(outgoing_message_id: outgoing.id)
    job = SendReplyJob.new
    expect(job).to(receive(:deliver).once { |message| message.update!(status: :failed) })
    job.perform(outgoing.id)
    expect(turn.reload.status).to eq('failed')
    expect(delegation.reload).to have_attributes(status: 'needs_human', reason: 'delivery_failed')
    expect(conversation.reload).to have_attributes(status: 'open', assignee_id: admin.id, assignee_agent_bot_id: nil)
    expect(JrcNico::Notice.where(account: account, user: admin, conversation: conversation, kind: 'attention').count).to eq(1)
    expect { job.perform(outgoing.id) }.not_to change(JrcNico::Notice, :count)
  end
end

