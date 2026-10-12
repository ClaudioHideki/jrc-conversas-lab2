require 'rails_helper'

RSpec.describe 'Protected native commercial effects', type: :model, approval_core: true, commercial_approvals: true do
  let(:scope) { approval_scope }
  let(:author) { approval_actor(scope, permissions: JrcApprovals::Authorization::PERMISSIONS + ['jrc_crm'], role: :administrator) }
  let(:approver) { approval_actor(scope, permissions: ['jrc_approvals_decide', 'jrc_crm']) }
  let(:fixture) { commercial_fixture(scope, author) }
  let(:proposal) { fixture[:proposal] }

  def native_send(proposal, key: nil)
    proposal.update!(approval_status: 'approved')
    create(:conversation, account: scope[:account], contact: proposal.customer_contact) unless proposal.customer_contact.conversations.exists?
    JrcCrm::ProposalDeliveryService.new(proposal: proposal, actor: author.user,
      base_url: 'https://synthetic.invalid', idempotency_key: key).call
  end

  def native_accepted(proposal)
    native_send(proposal)
    proposal.accept_by_customer!(name: 'Synthetic signer', document: 'synthetic', remote_ip: '127.0.0.1', user_agent: 'test')
    proposal.reload
  end

  it 'blocks sending in enforcement before PDF/message effects, then sends with both independent gates approved' do
    commercial_policy(scope, author, [approver])
    commercial_mode(scope[:account], 'crm.proposal_send', 'enforcement')
    record = commercial_request(scope, author, proposal).first
    expect { native_send(proposal, key: 'send-once') }.to raise_error(JrcApprovals::Error, 'APPROVAL_REQUIRED')
    expect(proposal.reload.sent_at).to be_nil
    expect(Message.where(account: scope[:account]).count).to eq(0)
    approval_vote(scope, approver, record)
    sent = native_send(proposal, key: 'send-once')
    expect(sent[:message].attachments.first.file.download).to start_with('%PDF-')
    expect(proposal.reload.status).to eq('sent')
    expect(native_send(proposal, key: 'send-once')[:message].id).to eq(sent[:message].id)
    expect(proposal.events.where(event_type: 'sent').count).to eq(1)
    expect(Message.where(account: scope[:account]).count).to eq(1)
  end

  it 'rejects a reused delivery key with different commercial content' do
    sent = native_send(proposal, key: 'once')
    proposal.update!(title: 'Another synthetic title')
    expect { native_send(proposal, key: 'once') }.to raise_error(JrcApprovals::Error, 'IDEMPOTENCY_CONTENT_CONFLICT')
    expect(Message.where(account: scope[:account]).pluck(:id)).to eq([sent[:message].id])
  end

  it 'requires an explicit effect idempotency key in enforcement while legacy/shadow resends remain compatible' do
    commercial_policy(scope, author, [approver])
    commercial_mode(scope[:account], 'crm.proposal_send', 'enforcement')
    record = commercial_request(scope, author, proposal).first
    approval_vote(scope, approver, record)
    expect { native_send(proposal) }.to raise_error(JrcApprovals::Error, 'IDEMPOTENCY_KEY_REQUIRED')
    expect(Message.where(account: scope[:account]).count).to eq(0)
  end

  it 'sends in shadow while preserving the legacy audit and approvals' do
    sent = native_send(proposal)
    expect(sent[:message].persisted?).to be(true)
    expect(proposal.events.find_by!(event_type: 'sent').user_id).to eq(author.user_id)
    expect(JrcApprovals::Request.where(account: scope[:account]).count).to eq(0)
  end

  it 'protects the delivery service itself from a legacy price/technical approval bypass' do
    proposal
    create(:conversation, account: scope[:account], contact: fixture[:contact])
    expect { JrcCrm::ProposalDeliveryService.new(proposal: proposal, actor: author.user).call }
      .to raise_error(ArgumentError, 'Os descontos ou requisitos técnicos exigem aprovação interna antes do envio.')
    expect(Message.where(account: scope[:account]).count).to eq(0)
  end

  it 'blocks conversion without its own gate, preserves idempotency and keeps operational approval pending' do
    native_accepted(proposal)
    commercial_policy(scope, author, [approver], key: 'crm.proposal_convert')
    commercial_mode(scope[:account], 'crm.proposal_convert', 'enforcement')
    expect { JrcCrm::ProposalToOrderService.new(proposal: proposal, actor: author.user).call }
      .to raise_error(JrcApprovals::Error, 'APPROVAL_REQUIRED')
    expect(proposal.sales_orders.count).to eq(0)
    record = commercial_request(scope, author, proposal, key: 'crm.proposal_convert').first
    approval_vote(scope, approver, record)
    order = JrcCrm::ProposalToOrderService.new(proposal: proposal, actor: author.user).call
    expect(JrcCrm::ProposalToOrderService.new(proposal: proposal, actor: author.user).call.id).to eq(order.id)
    expect(proposal.sales_orders.count).to eq(1)
    expect(order.status).to eq('pending')
    expect(order.backoffice_requests.where(request_kind: 'approval').count).to eq(1)
    expect(order.contracts.count).to eq(0)
  end

  it 'rejects an expired/revoked accepted source before conversion or replay' do
    native_accepted(proposal)
    proposal.update!(public_token_revoked_at: Time.current)
    expect { JrcCrm::ProposalToOrderService.new(proposal: proposal, actor: author.user).call }
      .to raise_error(JrcCrm::CommercialFinancials::InvalidTerms, 'Proposta expirada ou revogada não pode gerar pedido.')
    expect(proposal.sales_orders.count).to eq(0)
  end

  it 'does not convert an accepted label without legitimate send and acceptance records' do
    proposal.update_columns(status: 'accepted', sent_at: nil, accepted_at: nil)
    expect { JrcCrm::ProposalToOrderService.new(proposal: proposal.reload, actor: author.user).call }
      .to raise_error(JrcCrm::CommercialFinancials::InvalidTerms, 'O aceite exige envio e registro da data do aceite.')
    expect(proposal.sales_orders.count).to eq(0)
  end

  it 'uses the same native price evaluation for a direct order and prevents operational approval from bypassing it' do
    proposal
    order = JrcCrm::SalesOrder.create!(account: scope[:account], owner: author.user, created_by: author.user,
      contact: fixture[:contact], business_unit: scope[:unit], source_type: 'manual', status: 'pending')
    terms = proposal.financial_summary
    order.update!(JrcCrm::OrderFinancials.attributes_for(terms).merge(snapshot: JrcCrm::OrderFinancials.snapshot_for(terms)))
    terms[:items].each { |item| order.order_items.create!(item) }
    evaluation = JrcApprovals::NativePriceContext.new(order).call[:evaluation]
    expect(evaluation[:status]).to eq('evaluated')
    expect(evaluation[:items].first[:effective_unit_cents]).to eq(
      JrcApprovals::NativePriceContext.new(proposal).call[:evaluation][:items].first[:effective_unit_cents])
    commercial_policy(scope, author, [approver], key: 'crm.order_price')
    commercial_mode(scope[:account], 'crm.order_price', 'enforcement')
    legacy = order.backoffice_requests.find_by!(request_kind: 'approval')
    expect { JrcCrm::OrderApprovalService.new(order: order, actor: author.user).decide!(request: legacy, decision: 'approved') }
      .to raise_error(JrcApprovals::Error, 'APPROVAL_REQUIRED')
    expect(order.reload.status).to eq('pending')
    expect(legacy.reload.status).to eq('pending')
    record = commercial_request(scope, author, order, key: 'crm.order_price').first
    approval_vote(scope, approver, record)
    expect(order.reload.status).to eq('pending')
    JrcCrm::OrderApprovalService.new(order: order, actor: author.user).decide!(request: legacy, decision: 'approved')
    expect(order.reload.status).to eq('approved')
    expect(legacy.reload.status).to eq('approved')
    expect(order.backoffice_requests.where(request_kind: 'fulfillment').count).to eq(1)
  end

  it 'protects Backoffice release independently from operational approval and grants no vote to its operator' do
    native_accepted(proposal)
    order = JrcCrm::ProposalToOrderService.new(proposal: proposal, actor: author.user).call
    legacy = order.backoffice_requests.find_by!(request_kind: 'approval')
    commercial_policy(scope, author, [approver], key: 'backoffice.release')
    commercial_mode(scope[:account], 'backoffice.release', 'enforcement')
    expect { JrcCrm::OrderApprovalService.new(order: order, actor: author.user).decide!(request: legacy, decision: 'approved') }
      .to raise_error(JrcApprovals::Error, 'APPROVAL_REQUIRED')
    record = commercial_request(scope, author, legacy, key: 'backoffice.release').first
    approval_vote(scope, approver, record)
    JrcCrm::OrderApprovalService.new(order: order, actor: author.user).decide!(request: legacy, decision: 'approved')
    fulfillment = order.backoffice_requests.find_by!(request_kind: 'fulfillment')
    original_stage = fulfillment.stage
    expect { fulfillment.advance!(actor: author.user) }.to raise_error(JrcApprovals::Error, 'APPROVAL_REQUIRED')
    expect(fulfillment.reload.stage).to eq(original_stage)
  end

  it 'does not treat a signed name, customer PDF, client metadata or managerial approval as company signature evidence' do
    native_accepted(proposal)
    order = JrcCrm::ProposalToOrderService.new(proposal: proposal, actor: author.user).call
    JrcCrm::OrderApprovalService.new(order: order, actor: author.user)
      .decide!(request: order.backoffice_requests.find_by!(request_kind: 'approval'), decision: 'approved')
    contract = JrcCrm::Contract.create!(account: scope[:account], sales_order: order, owner: author.user,
      business_unit: scope[:unit], contact: fixture[:contact], signed_by_name: 'A name is not evidence',
      lifecycle_metadata: { 'company_signature_evidence' => 'verified' })
    commercial_policy(scope, author, [approver], key: 'contracts.company_signature')
    commercial_mode(scope[:account], 'contracts.company_signature', 'enforcement')
    record = commercial_request(scope, author, contract, key: 'contracts.company_signature').first
    approval_vote(scope, approver, record)
    expect { contract.with_lock { JrcApprovals::CommercialGate.check!(resource: contract, user: author.user, key: 'contracts.company_signature') } }
      .to raise_error(JrcApprovals::Error, 'COMPANY_SIGNATURE_EVIDENCE_REQUIRED')
    expect(contract.reload.status).to eq('draft')
    expect(contract.signed_document).not_to be_attached
  end

  it 'accepts only an explicit synthetic server evidence verifier plus the required approval' do
    native_accepted(proposal)
    order = JrcCrm::ProposalToOrderService.new(proposal: proposal, actor: author.user).call
    JrcCrm::OrderApprovalService.new(order: order, actor: author.user)
      .decide!(request: order.backoffice_requests.find_by!(request_kind: 'approval'), decision: 'approved')
    contract = JrcCrm::Contract.create!(account: scope[:account], sales_order: order, owner: author.user,
      business_unit: scope[:unit], contact: fixture[:contact])
    JrcApprovals::SignatureEvidence.verifier = lambda do |resource|
      { state: resource.id == contract.id && resource.account_id == scope[:account].id ? 'verified' : 'invalid',
        evidence_digest: Digest::SHA256.hexdigest("synthetic-company-proof:#{contract.id}:#{scope[:company].id}") }
    end
    commercial_policy(scope, author, [approver], key: 'contracts.company_signature')
    record = commercial_request(scope, author, contract, key: 'contracts.company_signature').first
    approval_vote(scope, approver, record)
    expect(JrcApprovals::CommercialGate.new(account: scope[:account], user: author.user)
      .evaluate(key: 'contracts.company_signature', resource_id: contract.id)[:status]).to eq('ready')
    expect(contract.reload.signature_status).to eq('not_started')
    JrcApprovals::SignatureEvidence.verifier = ->(*) { { state: 'verified', evidence_digest: Digest::SHA256.hexdigest('different-synthetic-proof') } }
    expect(JrcApprovals::CommercialGate.new(account: scope[:account], user: author.user)
      .evaluate(key: 'contracts.company_signature', resource_id: contract.id)[:status]).to eq('APPROVAL_REQUIRED')
  ensure
    JrcApprovals::SignatureEvidence.verifier = nil
  end
end
