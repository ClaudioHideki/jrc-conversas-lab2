require 'rails_helper'

RSpec.describe 'NICO commercial workflow' do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo', custom_attributes: { 'nico_enabled' => true }) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:operator) { JrcNico::OperatorSession.new(account: account, user: user) }
  let(:conversation) { create(:conversation, account: account) }
  let(:pipeline) { JrcCrm::DefaultPipelineService.new(account).perform }
  let(:product) { create(:jrc_crm_product, account: account, name: 'PABX 10 ramais', unit_price_cents: 10000, minimum_quantity: 2, billing_model: 'monthly', setup_fee_cents: 2500) }

  before { account.enable_features!('jrc_crm') }

  def execute(tool, args)
    command = operator.ask(message: "Execute #{tool}", request_id: SecureRandom.uuid, prepared: { 'tool' => tool, 'arguments' => args.stringify_keys })
    operator.execute(command)
    expect(command.reload.status).to eq('succeeded')
    command
  end

  def deal
    @deal ||= JrcCrm::Deal.find(execute('create_deal', title: 'Telefonia para o cliente', pipeline_id: pipeline.id,
      stage_id: pipeline.stages.first.id, contact_id: conversation.contact_id).result.dig('record', 'id'))
  end

  def proposal
    @proposal ||= JrcCrm::Proposal.find(execute('create_proposal', deal_id: deal.id).result.dig('record', 'id'))
  end

  it 'creates a contact and lead, prepares a priced commercial proposal and records the CRM meeting' do
    contact = Contact.find(execute('create_contact', name: 'Maria Comercial', email: 'maria@example.test', phone_number: '+5511991234567').result.dig('record', 'id'))
    lead = JrcCrm::Lead.find(execute('create_lead', contact_id: contact.id, notes: 'Precisa de PABX para sua equipe').result.dig('record', 'id'))
    expect(lead.contact).to eq(contact)
    expect(lead.owner).to eq(user)
    @deal = JrcCrm::Deal.find(execute('create_deal', title: 'Telefonia para Maria', pipeline_id: pipeline.id,
      stage_id: pipeline.stages.first.id, contact_id: contact.id).result.dig('record', 'id'))
    proposal
    execute('add_proposal_item', proposal_id: proposal.id, product_id: product.id, quantity: 2)
    execute('update_proposal', proposal_id: proposal.id, title: 'PABX para a equipe', solution_description: 'Telefonia conforme a necessidade registrada na conversa')
    item = proposal.proposal_items.sole
    expect(item).to have_attributes(unit_price_cents: 10000, quantity: 2, billing_model: 'monthly', setup_fee_cents: 2500)
    expect(proposal.reload).to have_attributes(status: 'draft', monthly_cents: 20000, implementation_cents: 2500)
    expect(proposal.sent_at).to be_nil
    date = 2.days.from_now.in_time_zone('America/Sao_Paulo').strftime('%Y-%m-%d')
    activity = JrcCrm::Activity.find(execute('create_activity', lead_id: lead.id, activity_type: 'meeting', title: 'Demonstração do PABX', due_at: "#{date}T15:00:00").result.dig('record', 'id'))
    expect(activity.due_at.utc.strftime('%H:%M')).to eq('18:00')
    expect(activity).to have_attributes(user_id: user.id, lead_id: lead.id, status: 'scheduled')
  end

  it 'preserves minimum quantity, integer storage and locked proposal rules without partial items' do
    proposal
    [1, 2.5].each do |quantity|
      expect { execute('add_proposal_item', proposal_id: proposal.id, product_id: product.id, quantity: quantity) }.to raise_error(ArgumentError)
      expect(proposal.proposal_items).to be_empty
    end
    expect { proposal.update!(status: 'accepted') }.to raise_error(ActiveRecord::RecordInvalid, /envio oficial/)
    # Represent the official delivery receipt before exercising the locked state.
    proposal.update!(status: 'sent', sent_at: Time.current)
    proposal.update!(status: 'accepted')
    expect { execute('add_proposal_item', proposal_id: proposal.id, product_id: product.id, quantity: 2) }.to raise_error(ArgumentError, /bloqueada/)
    expect(proposal.proposal_items).to be_empty
  end

  it 'rejects inactive products, foreign pipeline stages and model supplied prices' do
    proposal
    product.update!(active: false)
    expect { execute('add_proposal_item', proposal_id: proposal.id, product_id: product.id, quantity: 2) }.to raise_error(ActiveRecord::RecordNotFound)
    foreign_pipeline = create(:jrc_crm_pipeline)
    foreign_stage = create(:jrc_crm_stage, account: foreign_pipeline.account, pipeline: foreign_pipeline)
    expect { execute('create_deal', title: 'Wrong stage', pipeline_id: pipeline.id, stage_id: foreign_stage.id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { execute('add_proposal_item', proposal_id: proposal.id, product_id: product.id, quantity: 2, unit_price_cents: 1) }.to raise_error(ArgumentError)
  end

  it 'refuses duplicate meeting slots and past dates' do
    lead = create(:jrc_crm_lead, account: account, owner: user)
    args = { lead_id: lead.id, activity_type: 'meeting', title: 'Reunião', due_at: 2.days.from_now.iso8601 }
    execute('create_activity', args)
    expect { execute('create_activity', args) }.to raise_error(ArgumentError, /Já existe uma reunião/)
    expect { execute('create_activity', args.merge(due_at: 1.day.ago.iso8601)) }.to raise_error(ArgumentError, /futuros/)
    expect(account.jrc_crm_activities.count).to eq(1)
  end

  it 'continues a compound chat request from real results exactly once per completed step' do
    contexts = []
    allow(JrcNico::OperationalInference).to receive(:call) do |**input|
      contexts << input[:context]
      completed = input[:context][:completed_steps]
      if completed.empty?
        { 'tool' => 'create_contact', 'arguments' => { 'name' => 'Cliente composto', 'email' => 'compound@example.test' }, 'reply' => 'Criar contato' }
      elsif completed.size == 1
        { 'tool' => 'create_lead', 'arguments' => { 'contact_id' => completed.first[:result].dig('record', 'id') }, 'reply' => 'Criar o lead do contato cadastrado' }
      else
        { 'tool' => '', 'arguments' => {}, 'reply' => 'Contato e lead cadastrados.' }
      end
    end
    first = nil
    expect do
      first = operator.ask(message: 'Crie o contato e gere seu lead', request_id: SecureRandom.uuid)
    end.to(have_enqueued_job(JrcNico::ContinueCommandJob).with { |id| expect(id).to eq(first.id) })
    expect(first.status).to eq('succeeded')
    expect { operator.execute(first) }.not_to have_enqueued_job(JrcNico::ContinueCommandJob)
    JrcNico::ContinueCommandJob.perform_now(first.id)
    second = operator.session.commands.order(:id).last
    expect(second.tool).to eq('create_lead')
    expect(second.status).to eq('awaiting_confirmation')
    expect { JrcNico::ContinueCommandJob.perform_now(first.id) }.not_to change(JrcNico::Command, :count)
    operator.execute(second)
    JrcNico::ContinueCommandJob.perform_now(second.id)
    final = operator.session.commands.order(:id).last
    expect(final).to have_attributes(status: 'succeeded', tool: nil, reply: 'Contato e lead cadastrados.')
    expect(account.contacts.where(email: 'compound@example.test').count).to eq(1)
    expect(account.jrc_crm_leads.count).to eq(1)
    expect(contexts.last[:completed_steps].map { |step| step[:tool] }).to eq(%w[create_contact create_lead])
  end

  it 'does not resume an old workflow after a new operator request' do
    allow(JrcNico::OperationalInference).to receive(:call).and_return('tool' => 'create_contact', 'arguments' => { 'name' => 'Primeiro', 'email' => 'first@example.test' }, 'reply' => 'Criar')
    first = operator.ask(message: 'Crie contato e lead', request_id: SecureRandom.uuid)
    operator.execute(first)
    operator.ask(message: 'Outro contato', request_id: SecureRandom.uuid, prepared: { 'tool' => 'create_contact', 'arguments' => { 'name' => 'Outro', 'email' => 'other@example.test' } })
    expect { JrcNico::ContinueCommandJob.perform_now(first.id) }.not_to change(JrcNico::Command, :count)
  end

  it 'uses public conversation context and reuses its lead without replacing previous notes' do
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'Preciso de telefonia para dez pessoas')
    create(:message, account: account, conversation: conversation, private: true, content: 'NOTA_INTERNA')
    allow(JrcNico::OperationalInference).to receive(:call) do |**input|
      expect(input[:context][:conversation].to_json).to include('dez pessoas')
      expect(input[:context][:conversation].to_json).not_to include('NOTA_INTERNA')
      expect(input[:context][:selected_conversation][:contact_id]).to eq(conversation.contact_id)
      { 'tool' => 'create_lead', 'arguments' => { 'conversation_id' => conversation.display_id, 'notes' => 'Interesse em dez ramais' }, 'reply' => 'Registrar oportunidade' }
    end
    command = operator.ask(message: 'Identifique a oportunidade e gere o lead', request_id: SecureRandom.uuid, conversation_id: conversation.display_id)
    operator.execute(command)
    lead = account.jrc_crm_leads.sole
    expect(lead.notes).to eq('Interesse em dez ramais')
    expect { execute('create_lead', conversation_id: conversation.display_id, notes: 'Outro resumo') }.not_to change(JrcCrm::Lead, :count)
    expect(lead.reload.notes).to eq('Interesse em dez ramais')
  end
end
