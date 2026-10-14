require 'rails_helper'

RSpec.describe JrcCrm::Proposal, type: :model do
  let(:account) { create(:account) }
  let(:owner) { create(:user, account: account) }
  let(:pipeline) { JrcCrm::Pipeline.create!(account: account, name: 'Comercial', key: 'comercial', position: 1) }
  let(:stage) do
    JrcCrm::Stage.create!(account: account, pipeline: pipeline, name: 'Negociação', key: 'negociacao', position: 1)
  end
  let(:deal) do
    JrcCrm::Deal.create!(
      account: account,
      pipeline: pipeline,
      stage: stage,
      owner: owner,
      title: 'STIR/SHAKEN',
      value_cents: 0
    )
  end
  let(:proposal) do
    described_class.create!(
      account: account,
      deal: deal,
      owner: owner,
      title: 'Proposta — STIR/SHAKEN',
      discount_cents: 0
    )
  end
  let(:product) do
    JrcCrm::Product.create!(
      account: account,
      name: 'STIR/SHAKEN',
      sku: 'JRC-STIR-10000',
      product_type: 'service',
      billing_model: 'monthly',
      unit_price_cents: 2_500_00,
      setup_fee_cents: 1_500_00,
      maximum_discount_percent: 20,
      discount_approval_percent: 10
    )
  end

  it 'deriva implantação, recorrência e total inicial dos itens' do
    proposal.proposal_items.create!(
      product: product,
      name_snapshot: product.name,
      quantity: 1,
      unit_price_cents: product.unit_price_cents,
      setup_fee_cents: product.setup_fee_cents,
      billing_model: product.billing_model
    )

    proposal.reload

    expect(proposal.implementation_cents).to eq(1_500_00)
    expect(proposal.monthly_cents).to eq(2_500_00)
    expect(proposal.subtotal_cents).to eq(4_000_00)
    expect(proposal.total_cents).to eq(4_000_00)
  end

  it 'aplica descontos por item e desconto comercial sem permitir total negativo' do
    proposal.proposal_items.create!(
      product: product,
      name_snapshot: product.name,
      quantity: 1,
      unit_price_cents: product.unit_price_cents,
      setup_fee_cents: product.setup_fee_cents,
      billing_model: product.billing_model,
      discount_cents: 250_00
    )
    proposal.update!(discount_cents: 10_000_00)
    proposal.recalculate_totals!
    proposal.reload

    expect(proposal.item_discount_cents).to eq(250_00)
    expect(proposal.total_cents).to eq(0)
    expect(proposal.total_discount_cents).to eq(4_000_00)
  end

  it 'bloqueia edição depois do aceite' do
    proposal.update!(status: 'sent', sent_at: Time.current)
    proposal.accept_by_customer!(
      name: 'Cliente Teste',
      document: '000.000.000-00',
      remote_ip: '127.0.0.1',
      user_agent: 'RSpec'
    )

    expect(proposal).to be_locked_for_editing
    expect(proposal.status).to eq('accepted')
    expect(proposal.accepted_by_name).to eq('Cliente Teste')
  end
end
