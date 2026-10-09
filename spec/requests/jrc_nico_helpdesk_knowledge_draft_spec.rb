require 'rails_helper'

RSpec.describe 'HelpDesk human-generalized private knowledge drafts', type: :request do
  include_context 'NICO HelpDesk native action chain'

  let(:closed_ticket) do
    row = sd_ticket(company_id: company.id, title: 'Native historical case')
    lc_publish
    lc_execute(row, 'resolve', solution: 'PRIVATE ORIGINAL customer and operator evidence')
    lc_execute(row, 'close')
    row.reload
  end
  let(:close) { closed_ticket.lifecycle_transitions.where(action: 'close').order(:id).last }
  let(:draft_input) do
    { 'knowledge' => { 'closed_transition_id' => close.id, 'title' => 'Human generalized lesson',
      'body' => 'Reviewed generalized troubleshooting without customer identifiers.', 'generalization_reviewed' => true } }
  end

  before { sd_contact.update!(company_id: company.id) }

  it 'uses actual closed evidence and the existing approval chain, saving only reviewed private unapproved text' do
    event
    input = draft_input
    approval = nil
    expect { approval = prepare_native(input, 'prepare_closed_case_knowledge') }.not_to change(JrcNico::KnowledgeDocument, :count)
    expect { approve_native(approval) }.to change(JrcNico::KnowledgeDocument, :count).by(1)
    command = approved_action(approval)
    row = JrcNico::KnowledgeDocument.find(command.result.fetch('id'))
    expect(row).to have_attributes(account_id: sd_account.id, author_id: sd_user.id, customer_visible: false,
      approved_at: nil, approved_by_id: nil, title: input.dig('knowledge', 'title'), body: input.dig('knowledge', 'body'))
    expect(row.body).not_to include('PRIVATE ORIGINAL')
    expect(command.result.fetch('provenance')).to include('event_id' => event.id, 'closed_transition_id' => close.id,
      'command_id' => command.id, 'approval_id' => approval.id, 'request_id' => command.request_id)
    expect(approval.scope.dig('group', 'resources')).to include(['JrcServiceDesk::LifecycleTransition', close.id])
    get "/api/v1/accounts/#{sd_account.id}/jrc_nico/knowledge_documents", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(input.dig('knowledge', 'title'))
    get "#{base}/approvals", headers: headers
    expect(response.parsed_body.fetch('approvals').pluck('id')).to include(approval.id)
    expect do
      JrcNico::DomainAccess.authorize_resource!(JrcNico::OperationalAccess.new(account: sd_account, user: sd_user), row.class.name, row.id)
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect { approve_native(approval) }.not_to change(JrcNico::KnowledgeDocument, :count)
    expect(response).to have_http_status(:ok)
    expect(row.reload.approved_at).to be_nil
    expect(a_request(:any, %r{https?://})).not_to have_been_made
  end

  it 'offers authorized native closed transitions while leaving body and source unselected' do
    event
    closed_ticket
    result = action_preview({})
    expect(result.dig('draft_choices', 'knowledge', 'closed_cases').pluck('id')).to include(close.id)
    expect(result.fetch('actions')).to be_empty
    expect(JrcNico::KnowledgeDocument.where(account: sd_account)).to be_empty
  end

  it 'preserves the private operator chat after a draft without broadening approved knowledge, then clears it on source revocation' do
    approval = prepare_native(draft_input, 'prepare_closed_case_knowledge')
    approve_native(approval)
    command = approved_action(approval)
    previous = command.session.reload.messages
    expect(previous).not_to be_empty
    session = JrcNico::OperatorSession.new(account: sd_account, user: sd_user).session
    expect(session.reload.messages).to eq(previous)
    expect(session.context.fetch('resources')).to include(['JrcServiceDesk::LifecycleTransition', close.id])
    expect(session.context.fetch('resources')).not_to include(['JrcNico::KnowledgeDocument', command.result.fetch('id')])
    sd_membership.update!(active: false)
    renewed = JrcNico::OperatorSession.new(account: sd_account, user: sd_user).session
    expect(renewed.reload.messages).to be_empty
    verify_receipt_hidden(approval)
    expect(JrcNico::KnowledgeDocument.where(account: sd_account).approved).to be_empty
  end

  it 'rejects missing or false human review and any publication or private-source-copy flag' do
    input = draft_input
    [input.deep_merge('knowledge' => { 'generalization_reviewed' => false }),
     { 'knowledge' => input.fetch('knowledge').except('generalization_reviewed') },
     input.deep_merge('knowledge' => { 'customer_visible' => true }),
     input.deep_merge('knowledge' => { 'approved_at' => Time.current.iso8601 }),
     input.deep_merge('knowledge' => { 'copy_private_notes' => true }),
     input.deep_merge('knowledge' => { 'body' => nil }),
     input.deep_merge('knowledge' => { 'body' => 42 }),
     input.deep_merge('knowledge' => { 'closed_transition_id' => close.id.to_s })].each do |values|
      post "#{base}/group_preview", params: { event_id: event.id, group_key: selected_group, input: values }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'HELPDESK_INVALID_REQUEST')
    end
    expect(JrcNico::KnowledgeDocument.where(account: sd_account)).to be_empty
  end

  it 'rejects a closed case from another canonical customer in the same Unit' do
    input = draft_input
    other_company = JrcCustomers::Company.create!(account: sd_account, name: 'Other canonical customer')
    other_contact = create(:contact, account: sd_account, company_id: other_company.id)
    closed_ticket.update!(company_id: other_company.id, requester: other_contact)
    post "#{base}/group_preview", params: { event_id: event.id, group_key: selected_group, input: input }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcNico::KnowledgeDocument.where(account: sd_account)).to be_empty
  end

  it 'rechecks the native closed state before approval and forbids a reopened source' do
    approval = prepare_native(draft_input, 'prepare_closed_case_knowledge')
    lc_execute(closed_ticket, 'reopen')
    expect { approve_native(approval) }.not_to change(JrcNico::KnowledgeDocument, :count)
    expect(response).to have_http_status(:unauthorized)
    expect(approval.reload.state).to eq('pending')
  end

  it 'rechecks source Unit membership before preparation or approval' do
    approval = prepare_native(draft_input, 'prepare_closed_case_knowledge')
    sd_membership.update!(active: false)
    expect { approve_native(approval) }.not_to change(JrcNico::KnowledgeDocument, :count)
    expect(response).to have_http_status(:not_found)
  end

  it 'requires current native administrator authority even with an existing human approval' do
    approval = prepare_native(draft_input, 'prepare_closed_case_knowledge')
    sd_account_user.update!(role: :agent)
    expect { approve_native(approval) }.not_to change(JrcNico::KnowledgeDocument, :count)
    expect(response).to have_http_status(:unauthorized)
    verify_receipt_hidden(approval)
  end

  %w[body title customer_visible native_approval].each do |mutation|
    it "does not widen the private draft reader after native #{mutation} changes" do
      approval = prepare_native(draft_input, 'prepare_closed_case_knowledge')
      approve_native(approval)
      command = approved_action(approval)
      row = JrcNico::KnowledgeDocument.find(command.result.fetch('id'))
      case mutation
      when 'body' then row.update!(body: 'Changed outside original reviewed command')
      when 'title' then row.update!(title: 'Changed title')
      when 'customer_visible' then row.update!(customer_visible: true)
      when 'native_approval' then row.update!(approved_by: sd_user, approved_at: Time.current)
      end
      verify_receipt_hidden(approval)
      expect { approve_native(approval) }.not_to change(JrcNico::KnowledgeDocument, :count)
      expect(response.parsed_body).to be_nil
    end
  end
end
