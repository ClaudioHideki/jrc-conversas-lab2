require 'rails_helper'

RSpec.describe JrcBackoffice::SignatureRelease do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }
  let(:order) { account.jrc_crm_sales_orders.create!(owner: actor, contact: contact, status: 'approved') }
  let(:contract) { account.jrc_crm_contracts.create!(sales_order: order, owner: actor, contact: contact) }
  let(:request) do
    account.jrc_crm_backoffice_requests.create!(sales_order: order, contract: contract, owner: actor, requested_by: actor,
                                                request_kind: 'fulfillment', stage: 'contract', contact: contact,
                                                title: 'TESTE SINTÉTICO — Liberação contratual',
                                                metadata: { contract_required: true, implementation_required: true })
  end
  let(:signed_file) { Rails.root.join('spec/fixtures/files/sample.pdf') }

  before { JrcApprovals::SignatureEvidence.verifier = nil }

  it 'preserves the native manual signature semantics for a legacy contract without a v2 request' do
    contract.signed_document.attach(io: File.open(signed_file), filename: 'synthetic-manual.pdf', content_type: 'application/pdf')
    contract.update!(signature_status: 'signed', signed_at: Time.current, signed_by_name: 'TESTE SINTÉTICO — Legado')
    legacy = JrcCrm::BackofficeRequest.new(sales_order: order, contract: contract, workflow_version: 1)
    expect(described_class.satisfied?(legacy)).to be(true)
    expect(contract.reload.signature_status).to eq('signed')
  end

  it 'does not release v2 implementation because an older contract has a manual signed flag' do
    contract.signed_document.attach(io: File.open(signed_file), filename: 'synthetic-manual.pdf', content_type: 'application/pdf')
    contract.update!(signature_status: 'signed', signed_at: Time.current, signed_by_name: 'TESTE SINTÉTICO — Legado')
    expect(request.workflow_version).to eq(2)
    expect(request.stage_blockers).to include(described_class::MESSAGE)
    expect { request.advance!(actor: actor) }.to raise_error(ActiveRecord::RecordInvalid, /O contrato precisa estar assinado/)
    expect(request.reload.stage).to eq('contract')
    expect(contract.reload.signature_status).to eq('signed')
    expect { order.update!(status: 'separating') }.to raise_error(ActiveRecord::RecordInvalid, /O contrato precisa estar assinado/)
    expect(order.reload.status).to eq('approved')
  end

  it 'records the customer signature independently without granting operational activation or release' do
    request
    contract.signed_document.attach(io: File.open(signed_file), filename: 'synthetic-manual.pdf', content_type: 'application/pdf')
    contract.update!(signature_status: 'signed', signed_at: Time.current, signed_by_name: 'TESTE SINTÉTICO — Sem evidências',
                     status: 'awaiting_signature')
    expect(contract.reload.signature_status).to eq('signed')
    expect(described_class.verified?(contract)).to be(false)
    expect(described_class.order_satisfied?(order)).to be(false)
    expect(request.reload.stage).to eq('contract')
  end
end
