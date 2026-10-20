require 'rails_helper'

RSpec.describe 'NICO JSON execution boundary', type: :request do
  around { |example| perform_enqueued_jobs(only: JrcNico::PlanCommandJob) { example.run } }
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo', custom_attributes: { 'nico_enabled' => true }) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:headers) { user.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_nico/operations" }
  let(:operator) { JrcNico::OperatorSession.new(account: account, user: user) }
  let(:access) { JrcNico::OperationalAccess.new(account: account, user: user).authorize! }
  let(:executor) { JrcNico::ToolExecutor.new(access) }
  let(:contact) { create(:contact, account: account, name: 'Telmo Miranda', phone_number: '+5511991234567') }
  let(:conversation) { create(:conversation, account: account, contact: contact, status: :open) }

  before { account.enable_features!('jrc_crm') }

  it 'does not execute any tool or mutate resources on invalid runtime output, and shows the technical failure' do
    with_modified_env NICO_RUNTIME_URL: 'http://runtime:3108', NICO_SERVICE_TOKEN: 'test-only-not-for-production-12345678' do
      stub_request(:post, 'http://runtime:3108/v1/operate').to_return(status: 502, body: { error: 'tool_arguments_invalid' }.to_json)
      expect(JrcNico::ToolExecutor).not_to receive(:new)
      counts = [Contact.count, JrcCrm::Lead.count, JrcCrm::Activity.count, JrcCrm::Deal.count]
      post "#{base}/ask", params: { request_id: SecureRandom.uuid, message: 'Crie um contato e lead' }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('commands').first.fetch('status')).to eq('failed')
      expect(response.parsed_body.fetch('commands').first.fetch('reply')).to include('Nenhuma alteração foi realizada')
      expect([Contact.count, JrcCrm::Lead.count, JrcCrm::Activity.count, JrcCrm::Deal.count]).to eq(counts)
      expect(JrcNico::Command.last).to have_attributes(status: 'failed', tool: nil)
      expect(JrcNico::Command.last.reply).to include('interpretar os dados')
    end
  end

  it 'keeps writes pending after a valid retry result and confirms a contact exactly once' do
    wire = JSON.parse(Rails.root.join('services/nico-runtime/test/fixtures/operation-contract.json').read)
    with_modified_env NICO_RUNTIME_URL: 'http://runtime:3108', NICO_SERVICE_TOKEN: 'test-only-not-for-production-12345678' do
      stub_request(:post, 'http://runtime:3108/v1/operate').to_return do |request|
        payload = JSON.parse(request.body)
        { status: 200, body: wire.merge('request_id' => payload['request_id'], 'account_id' => account.id).to_json }
      end
      request_id = SecureRandom.uuid
      2.times do
        expect do
          post "#{base}/ask", params: { request_id: request_id, message: 'Crie Telmo' }, headers: headers, as: :json
        end.not_to change(Contact, :count)
      end
      command = operator.session.commands.where(request_id: request_id).sole
      expect(command.status).to eq('awaiting_confirmation')
      expect { post "#{base}/commands/#{command.id}/confirm", headers: headers, as: :json }.to change(Contact, :count).by(1)
      expect { post "#{base}/commands/#{command.id}/confirm", headers: headers, as: :json }.not_to change(Contact, :count)
      expect(WebMock).to have_requested(:post, 'http://runtime:3108/v1/operate').once
    end
  end

  it 'repeatedly counts and lists contacts without query, and lists open/pending conversations' do
    contact
    conversation
    waiting = create(:conversation, account: account, status: :pending)
    other_account_contact = create(:contact)
    5.times do
      expect(executor.call('count_contacts', {})).to eq(count: account.contacts.count)
      expect(executor.call('list_contacts', {}).map { |row| row['id'] }).to include(contact.id)
      expect(executor.call('list_contacts', {}).map { |row| row['id'] }).not_to include(other_account_contact.id)
      expect(executor.call('list_conversations', 'status' => 'open').map { |row| row[:conversation_id] }).to include(conversation.display_id)
      expect(executor.call('list_conversations', 'status' => 'pending').map { |row| row[:conversation_id] }).to include(waiting.display_id)
    end
  end

  it 'rejects unknown tools, unknown arguments and incorrect types before execution' do
    catalog = JrcNico::ToolCatalog.new(access)
    expect { catalog.validate!('destroy_everything', {}) }.to raise_error(Pundit::NotAuthorizedError)
    expect { catalog.validate!('count_contacts', 'query' => 'Telmo') }.to raise_error(ArgumentError, /Campo não permitido/)
    expect { catalog.validate!('update_contact', 'contact_id' => '123') }.to raise_error(ArgumentError, /Valor inválido/)
    expect { catalog.validate!('create_activity', 'title' => 'Teste', 'due_at' => Time.current.iso8601, 'activity_type' => 'meeting') }
      .to raise_error(ArgumentError, /lead_id ou deal_id/)
    %w[create_contact update_contact create_lead update_lead create_deal create_activity update_activity send_message update_conversation
       create_proposal update_proposal create_campaign campaign_action set_reporting_timezone].each do |tool|
      expect(catalog.available.find { |row| row[:name] == tool }).to include(confirmation: true) if catalog.available.any? { |row| row[:name] == tool }
    end
  end

  it 'presents names and phones, accepts a phone choice and blocks a silent recipient choice' do
    conversation
    duplicate = create(:contact, account: account, name: 'Telmo Miranda', phone_number: '+5511981234567')
    create(:conversation, account: account, contact: duplicate)
    allow(JrcNico::OperationalInference).to receive(:call).and_return('reply' => '', 'tool' => 'search_contacts', 'arguments' => { 'query' => 'Telmo Miranda' })
    command = operator.ask(message: 'Localize o contato Telmo Miranda.', request_id: SecureRandom.uuid)
    expect(command.reply).to include(contact.name, contact.phone_number, duplicate.phone_number,
                                     conversation.inbox.channel_type.delete_prefix('Channel::'))
    expect(account.contacts.count).to eq(2)
    allow(JrcNico::OperationalInference).to receive(:call).and_return('reply' => 'Assumir', 'tool' => 'update_conversation',
      'arguments' => { 'conversation_id' => conversation.display_id, 'assignee_id' => user.id })
    expect { operator.ask(message: 'Assuma a conversa mais recente do Telmo.', request_id: SecureRandom.uuid) }
      .to raise_error(ArgumentError, /contatos ambíguos/)
    chosen = operator.ask(message: "Assuma a conversa do telefone #{contact.phone_number}.", request_id: SecureRandom.uuid)
    expect(chosen.status).to eq('awaiting_confirmation')
    operator.execute(chosen)
    expect(conversation.reload.assignee_id).to eq(user.id)
  end

  [false, true].each do |existing_lead|
    it "continues Telmo's confirmed lead/meeting workflow once (existing lead: #{existing_lead})" do
      travel_to Time.zone.parse('2026-09-14T12:00:00Z') do
        conversation
        lead = create(:jrc_crm_lead, account: account, owner: user, contact: contact) if existing_lead
        create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'Quero uma demonstração de PABX amanhã às 10h')
        allow(JrcNico::OperationalInference).to receive(:call) do |**input|
          context = input[:context]
          completed = context[:completed_steps]
          reads = context[:tool_results]
          expect(context[:timezone]).to eq('America/Sao_Paulo')
          if completed.any? { |step| step[:tool] == 'create_activity' }
            { 'tool' => '', 'arguments' => {}, 'reply' => "Reunião registrada ##{completed.last[:result].dig('record', 'id')}; nenhum convite externo foi enviado." }
          elsif completed.any? || (reads.last && reads.last[:tool] == 'list_leads' && existing_lead)
            lead_id = lead&.id || completed.last[:result].dig('record', 'id')
            { 'tool' => 'create_activity', 'arguments' => { 'lead_id' => lead_id, 'title' => 'Demonstração de PABX', 'activity_type' => 'meeting',
              'due_at' => '2026-09-15T10:00:00-03:00' }, 'reply' => 'Agendar reunião para amanhã às 10h' }
          else
            tool, arguments = [
              ['search_contacts', { 'query' => 'Telmo Miranda' }], ['list_conversations', { 'query' => 'Telmo Miranda' }],
              ['read_conversation', { 'conversation_id' => conversation.display_id }], ['list_leads', { 'contact_id' => contact.id }],
              ['create_lead', { 'conversation_id' => conversation.display_id }]
            ].fetch(reads.size)
            { 'tool' => tool, 'arguments' => arguments, 'reply' => 'Preparar próxima etapa' }
          end
        end
        message = 'Entre na conversa do Telmo, crie ou reutilize o lead e agende uma reunião para amanhã às 10 horas no fuso padrão da conta.'
        command = operator.ask(message: message, request_id: SecureRandom.uuid)
        expect(command.status).to eq('awaiting_confirmation')
        expect(account.jrc_crm_activities.count).to eq(0)
        unless existing_lead
          expect(command.tool).to eq('create_lead')
          expect { operator.execute(command) }.to change(JrcCrm::Lead, :count).by(1)
          operator.execute(command)
          JrcNico::ContinueCommandJob.perform_now(command.id)
          expect { JrcNico::ContinueCommandJob.perform_now(command.id) }.not_to change(JrcNico::Command, :count)
          command = operator.session.commands.order(:id).last
          expect(command.status).to eq('awaiting_confirmation')
        end
        expect(command.tool).to eq('create_activity')
        expect { operator.execute(command) }.to change(JrcCrm::Activity, :count).by(1)
        expect { operator.execute(command) }.not_to change(JrcCrm::Activity, :count)
        JrcNico::ContinueCommandJob.perform_now(command.id)
        expect(account.jrc_crm_activities.sole.due_at.utc.iso8601).to eq('2026-09-15T13:00:00Z')
        expect(account.jrc_crm_leads.count).to eq(1)
        expect(operator.session.commands.order(:id).last.reply).to include('nenhum convite externo foi enviado')
        expect(conversation.messages.outgoing.count).to eq(0)
      end
    end
  end

  it 'does not repeat a completed write when the continuation provider fails' do
    allow(JrcNico::OperationalInference).to receive(:call).and_return('tool' => 'create_contact', 'arguments' => { 'name' => 'Telmo', 'email' => 'telmo@example.test' }, 'reply' => 'Criar')
    command = operator.ask(message: 'Crie contato e lead', request_id: SecureRandom.uuid)
    operator.execute(command)
    allow(JrcNico::OperationalInference).to receive(:call).and_raise(JrcNico::RuntimeClient::Error.new('tool_arguments_invalid'))
    2.times { JrcNico::ContinueCommandJob.perform_now(command.id) }
    failed = operator.session.commands.order(:id).last
    expect(failed.status).to eq('failed')
    expect(failed.reply).to include('etapas já concluídas foram preservadas')
    expect(failed.reply).not_to include('Nenhuma alteração foi realizada')
    expect(account.contacts.where(email: 'telmo@example.test').count).to eq(1)
    expect(account.jrc_crm_leads.count).to eq(0)
  end

  it 'reads public evidence across all statuses in bounded batches and reports real opportunity IDs' do
    records = 12.times.map do |index|
      record = create(:conversation, account: account, status: %w[open pending resolved snoozed][index % 4])
      create(:message, account: account, conversation: record, message_type: :incoming, content: 'Quero comprar dez ramais de PABX')
      create(:message, account: account, conversation: record, private: true, content: 'PRIVATE_INTERNAL_NOTE')
      record.update!(status: %w[open pending resolved snoozed][index % 4])
      record
    end
    contexts = []
    allow(JrcNico::OperationalInference).to receive(:call) do |**input|
      contexts << input[:context].deep_dup
      results = input[:context][:tool_results]
      if results.size < 2
        { 'tool' => 'conversation_opportunity_batch', 'arguments' => { 'page' => results.size + 1 }, 'reply' => '' }
      else
        rows = results.flat_map { |item| item[:result][:conversations] }
        { 'tool' => '', 'arguments' => {}, 'reply' => "Analisei #{rows.size} conversas visíveis de todos os status, até 5 mensagens públicas cada. Interesse em PABX nas conversas #{rows.map { |row| row[:conversation_id] }.join(', ')}. Nenhum lead foi criado. Amostra limitada às 200 mais recentes." }
      end
    end
    command = operator.ask(message: 'Analise as conversas visíveis em todos os status e identifique oportunidades para criar leads.', request_id: SecureRandom.uuid)
    rows = contexts.last[:tool_results].flat_map { |item| item[:result][:conversations] }
    expect(rows.map { |row| row[:conversation_id] }).to match_array(records.map(&:display_id))
    expect(rows.map { |row| row[:status] }.uniq).to match_array(%w[open pending resolved snoozed])
    expect(rows.to_json).not_to include('PRIVATE_INTERNAL_NOTE')
    expect(command.reply).to include('Analisei 12', '200 mais recentes')
    expect(command.reply).not_to include('Consultei os dados disponíveis')
    expect(account.jrc_crm_leads.count).to eq(0)
  end
  it 'rechecks access to conversations nested in contact results before retaining history' do
    conversation
    allow(JrcNico::OperationalInference).to receive(:call).and_return(
      { 'reply' => '', 'tool' => 'search_contacts', 'arguments' => { 'query' => 'Telmo Miranda' } },
      { 'reply' => 'Contato localizado.', 'tool' => '', 'arguments' => {} }
    )
    operator.ask(message: 'Localize Telmo Miranda', request_id: SecureRandom.uuid)
    expect(operator.session.context['conversation_ids']).to include(conversation.display_id)
    allow(JrcNico::OperationalAccess).to receive(:new).and_return(access)
    allow(access).to receive(:conversation).with(conversation.display_id).and_raise(Pundit::NotAuthorizedError)
    renewed = JrcNico::OperatorSession.new(account: account, user: user)
    expect(renewed.session.messages).to be_empty
  end

  it 'reuses a contact-linked lead across confirmed commands without replacing its notes' do
    lead = create(:jrc_crm_lead, account: account, owner: user, contact: contact, notes: 'Notas originais')
    command = operator.ask(message: 'Crie ou reutilize o lead', request_id: SecureRandom.uuid,
      prepared: { 'tool' => 'create_lead', 'arguments' => { 'contact_id' => contact.id, 'notes' => 'Novas notas' } })
    expect(command.status).to eq('awaiting_confirmation')
    expect { operator.execute(command) }.not_to change(JrcCrm::Lead, :count)
    expect(command.result.dig('record', 'id')).to eq(lead.id)
    expect(lead.reload.notes).to eq('Notas originais')
  end

  it 'limits opportunity batches to the agent inbox scope' do
    conversation
    hidden = create(:conversation, account: account)
    create(:conversation)
    agent = create(:user, account: account, role: :agent)
    create(:inbox_member, inbox: conversation.inbox, user: agent)
    scoped_access = JrcNico::OperationalAccess.new(account: account, user: agent).authorize!
    result = JrcNico::ToolExecutor.new(scoped_access).call('conversation_opportunity_batch', {})
    expect(result[:conversations].map { |row| row[:conversation_id] }).to eq([conversation.display_id])
    expect(result[:conversations].map { |row| row[:conversation_id] }).not_to include(hidden.display_id)
    expect(result[:scope]).to include('permissões')
    expect(result[:next_page]).to be_nil
  end

  it 'stops at the read budget and returns real scope instead of the generic fallback' do
    conversation
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'Tenho interesse em PABX')
    allow(JrcNico::OperationalInference).to receive(:call).and_return('reply' => '', 'tool' => 'conversation_opportunity_batch', 'arguments' => {})
    command = operator.ask(message: 'Analise as oportunidades', request_id: SecureRandom.uuid)
    expect(JrcNico::OperationalInference).to have_received(:call).exactly(8).times
    expect(command.reply).to include('Foram lidas 1 conversas', 'cinco mensagens públicas', "##{conversation.display_id}", 'somente consultas')
    expect(command.reply).not_to include('Consultei os dados disponíveis')
    expect(account.jrc_crm_leads.count).to eq(0)
  end

  it 'forces a real opportunity read when the provider returns the generic no-op answer' do
    conversation
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'Precisamos de dez ramais para a empresa')
    allow(JrcNico::OperationalInference).to receive(:call).and_return(
      'reply' => 'Consultei os dados disponíveis. Selecione o registro ou detalhe a próxima ação.', 'tool' => '', 'arguments' => {}
    )

    command = operator.ask(message: 'Analise todas as conversas e identifique oportunidades para gerar leads', request_id: SecureRandom.uuid)

    expect(command.reply).to include("Conversa ##{conversation.display_id}", conversation.contact.name, 'dez ramais')
    expect(command.reply).to include('nenhum lead foi criado sem confirmação')
    expect(command.reply).not_to include('Consultei os dados disponíveis')
    expect(account.jrc_crm_leads.count).to eq(0)
  end

  it 'replans a hallucinated unauthorized tool using the catalog instead of denying the operator' do
    allow(JrcNico::OperationalInference).to receive(:call).and_return(
      { 'reply' => '', 'tool' => 'delete_everything', 'arguments' => {} },
      { 'reply' => '', 'tool' => 'count_contacts', 'arguments' => {} },
      { 'reply' => 'A conta possui contatos cadastrados.', 'tool' => '', 'arguments' => {} }
    )

    command = operator.ask(message: 'Quantos contatos temos cadastrados?', request_id: SecureRandom.uuid)

    expect(command.status).to eq('succeeded')
    expect(command.reply).to eq('A conta possui contatos cadastrados.')
    expect(command.reply).not_to include('Seu perfil não permite')
  end

  it 'reuses an identical contact count instead of exhausting the read budget' do
    create_list(:contact, 2, account: account)
    allow(JrcNico::OperationalInference).to receive(:call).and_return(
      'reply' => '', 'tool' => 'count_contacts', 'arguments' => {}
    )

    command = operator.ask(message: 'Quantos contatos temos cadastrados?', request_id: SecureRandom.uuid)

    expect(JrcNico::OperationalInference).to have_received(:call).twice
    expect(command.reply).to eq("Há #{account.contacts.count} contatos cadastrados na conta.")
    expect(command.reply).not_to include('limite de consultas', 'count_contacts:')
  end

end
