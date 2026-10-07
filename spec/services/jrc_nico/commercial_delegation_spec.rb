require 'rails_helper'

RSpec.describe 'NICO commercial delegation' do
  let(:account) { create(:account, custom_attributes: { 'nico_enabled' => true, 'nico_customer_delegation_enabled' => true }) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, account: account) }
  let(:operator) { JrcNico::OperatorSession.new(account: account, user: user) }
  let(:delegation) { JrcNico::Delegation.find_by!(conversation: conversation) }
  let(:notice) do
    JrcNico::Notice.publish!(account: account, user: user, conversation: conversation, event_key: SecureRandom.uuid,
      kind: 'action', request: 'Cadastre os dados e marque a reunião', body: 'Pedido do cliente',
      metadata: { delegation_id: delegation.id, delegation_version: delegation.version })
  end

  before { account.enable_features!('jrc_crm') }

  it 'leaves customer attendance to bots unless account delegation is explicitly enabled' do
    account.update!(custom_attributes: { 'nico_enabled' => true })
    expect { delegate([]) }.to raise_error(ArgumentError, /assistente interno/)
    expect(JrcNico::Delegation.where(account: account)).to be_empty
  end

  def delegate(actions)
    with_modified_env NICO_MODE: 'provider' do
      JrcNico::DelegationService.new(operator.access).start('conversation_ids' => [conversation.display_id],
        'objective' => 'Atender comercialmente', 'allowed_actions' => actions)
    end
  end

  def plan(tool, args)
    allow(JrcNico::OperationalInference).to receive(:call).and_return('tool' => tool, 'arguments' => args.stringify_keys, 'reply' => 'Próxima ação')
    JrcNico::NoticePlanJob.perform_now(notice.id)
    notice.commands.order(:id).last
  end

  it 'updates the current contact and schedules its meeting using the selected delegation permissions' do
    delegate(%w[contacts meetings])
    command = plan('update_contact', contact_id: conversation.contact_id, email: 'atendimento@example.test')
    expect(command.status).to eq('succeeded')
    expect(command.execution_context.dig('authorization', 'source')).to eq('delegation')
    expect(conversation.contact.reload.email).to eq('atendimento@example.test')
    lead_command = plan('create_lead', conversation_id: conversation.display_id, notes: 'Cliente quer uma demonstração')
    expect(lead_command.status).to eq('succeeded')
    meeting = plan('create_activity', lead_id: lead_command.result.dig('record', 'id'), activity_type: 'meeting', title: 'Demonstração', due_at: 2.days.from_now.iso8601)
    expect(meeting.status).to eq('succeeded')
    expect(account.jrc_crm_activities.sole.lead.contact_id).to eq(conversation.contact_id)
  end

  it 'requires operator review for actions outside the selected permission categories' do
    delegate([])
    command = plan('update_contact', contact_id: conversation.contact_id, email: 'unapproved@example.test')
    expect(command.status).to eq('awaiting_confirmation')
    expect(conversation.contact.reload.email).not_to eq('unapproved@example.test')
  end

  it 'prepares the conversation proposal on the server and leaves sending for operator review' do
    delegate(['proposals'])
    pipeline = JrcCrm::DefaultPipelineService.new(account).perform
    product = create(:jrc_crm_product, account: account, unit_price_cents: 18000)
    deal_command = plan('create_deal', title: 'Telefonia empresarial', pipeline_id: pipeline.id,
      stage_id: pipeline.stages.first.id, contact_id: conversation.contact_id)
    expect(deal_command.status).to eq('succeeded')
    proposal_command = plan('create_proposal', deal_id: deal_command.result.dig('record', 'id'))
    expect(proposal_command.status).to eq('succeeded')
    proposal_id = proposal_command.result.dig('record', 'id')
    item_command = plan('add_proposal_item', proposal_id: proposal_id, product_id: product.id, quantity: 3)
    expect(item_command.status).to eq('succeeded')
    proposal = JrcCrm::Proposal.find(proposal_id)
    expect(proposal.proposal_items.sole.total_cents).to eq(54000)
    expect(proposal.status).to eq('draft')
    expect(plan('send_proposal', proposal_id: proposal_id, channel: 'auto').status).to eq('awaiting_confirmation')
    expect(proposal.reload.sent_at).to be_nil
  end

  it 'excludes private fields and revoked resources from customer-facing completion context' do
    delegate(['meetings'])
    command = plan('create_lead', conversation_id: conversation.display_id)
    command.update!(result: command.result.deep_merge('record' => { 'notes' => 'SEGREDO_INTERNO' }))
    context = JrcNico::CustomerTurnJob.new.send(:completed_actions, delegation)
    expect(context.to_json).not_to include('SEGREDO_INTERNO')
    expect(context.first[:record]['id']).to eq(command.result.dig('record', 'id'))
    account.disable_features!('jrc_crm')
    expect(JrcNico::CustomerTurnJob.new.send(:completed_actions, delegation)).to eq([])
  end

  it 'rejects customer attempts to act on another contact' do
    delegate(['contacts'])
    other = create(:contact, account: account, name: 'Outro cliente')
    command = plan('update_contact', contact_id: other.id, name: 'Intrusão')
    expect(command.status).to eq('failed')
    expect(other.reload.name).to eq('Outro cliente')
  end

  it 'prepares one delegated SIP call, claims it once and records only browser-reported initiation' do
    create(:sip_credential, account: account, user: user)
    conversation.contact.update!(phone_number: '+5511991234567')
    delegate(['calls'])
    command = plan('call_contact', contact_id: conversation.contact_id)
    expect(command.status).to eq('browser_pending')
    expect(command.result['browser_action']).to eq('sip_call')
    operator.browser_claim(command)
    expect { operator.browser_claim(command) }.to raise_error(JrcNico::OperatorSession::Busy)
    operator.browser_result(command, 'succeeded', 'Discagem iniciada pelo ramal')
    expect(command.reload.result['browser_status']).to eq('succeeded')
  end

  it 'cancels queued automatic calls when the operator takes over' do
    create(:sip_credential, account: account, user: user)
    conversation.contact.update!(phone_number: '+5511991234567')
    delegate(['calls'])
    command = plan('call_contact', contact_id: conversation.contact_id)
    JrcNico::DelegationService.stop(conversation, reason: 'human_takeover', user: user)
    expect(command.reload.status).to eq('cancelled')
    expect { operator.browser_claim(command) }.to raise_error(JrcNico::OperatorSession::Busy)
  end

  it 'requires a fresh call preview when the contact telephone changes before claiming' do
    create(:sip_credential, account: account, user: user)
    conversation.contact.update!(phone_number: '+5511991234567')
    delegate(['calls'])
    command = plan('call_contact', contact_id: conversation.contact_id)
    conversation.contact.update!(phone_number: '+5511997654321')
    expect { operator.browser_claim(command) }.to raise_error(ArgumentError, /telefone do contato mudou/)
    expect(command.reload.status).to eq('browser_pending')
  end

  it 'does not reuse a previous delegation authorization after takeover and redelegation' do
    delegate(['contacts'])
    old_notice = notice
    JrcNico::DelegationService.stop(conversation, reason: 'human_takeover', user: user)
    delegate(['contacts'])
    command = operator.session.commands.create!(source_notice: old_notice, request_id: SecureRandom.uuid,
      message: old_notice.request, tool: 'update_contact', arguments: { contact_id: conversation.contact_id, name: 'Não autorizado' }, status: 'awaiting_confirmation')
    expect(JrcNico::DelegatedActions.permitted?(delegation.reload, command, operator.access)).to be(false)
    expect { operator.execute(command, delegation: delegation) }.to raise_error(Pundit::NotAuthorizedError)
    expect(conversation.contact.reload.name).not_to eq('Não autorizado')
  end

  it 'restricts customer request searches to the conversation contact' do
    delegate(['meetings'])
    current = create(:jrc_crm_lead, account: account, owner: user, contact: conversation.contact)
    other = create(:jrc_crm_lead, account: account, owner: user, notes: 'NOTA_OUTRO_CLIENTE')
    rows = JrcNico::ToolExecutor.new(operator.access, customer_notice: notice).call('list_leads', {})
    expect(rows.map { |row| row['id'] }).to eq([current.id])
    expect(rows.to_json).not_to include(other.notes)
  end

  it 'leaves a finished request at rest when its planning job is redelivered' do
    delegate([])
    allow(JrcNico::OperationalInference).to receive(:call).and_return('tool' => '', 'arguments' => {}, 'reply' => 'Qual horário você prefere?')
    JrcNico::NoticePlanJob.perform_now(notice.id)
    expect(notice.reload.status).to eq('review')
    expect { JrcNico::NoticePlanJob.perform_now(notice.id) }.not_to change(JrcNico::Command, :count)
  end
end
