require 'rails_helper'

RSpec.describe 'Fixed monthly proposal financials' do
  let(:attributes) { { financial_version: 3, term_months: 36, payment_condition: 'installments', installments_count: 36, first_due_date: '2026-10-26' } }
  let(:monthly) { { name: 'Fixed subscription', quantity: 1, unit_cents: 29_500, snapshot: { billing_model: 'monthly', setup_fee_cents: 0 } } }

  it 'keeps 36 monthly fees of 295 reais and forecasts 10620 reais without financing a single monthly fee' do
    result = JrcCrm::CommercialFinancials.new(attributes: attributes, items: [monthly]).call
    expect(result).to include(total_cents: 29_500, monthly_cents: 29_500, recurring_months_count: 36, payable_base_cents: 0,
                             recurring_total_cents: 1_062_000, contract_total_cents: 1_062_000, installment_plan_cents: [])
    expect(result[:recurring_schedule]).to include(count: 36, amount_cents: 29_500, frequency: 'monthly', forecast_only: true)
    expect(result[:payments]).to contain_exactly(kind: 'first_monthly', date: '2026-10-26', value: 29_500)
  end

  it 'finances implementation and a one-time product independently with exact cent conservation' do
    one_time = { quantity: 1, unit_cents: 10_001, snapshot: { billing_model: 'one_time', setup_fee_cents: 2_000 } }
    result = JrcCrm::CommercialFinancials.new(attributes: attributes.merge(installments_count: 3), items: [monthly, one_time]).call
    expect(result[:installment_plan_cents]).to eq([4_001, 4_000, 4_000])
    expect(result[:payments].reject { |row| row[:kind] == 'first_monthly' }.sum { |row| row[:value] }).to eq(12_001)
    expect(result[:payments].sum { |row| row[:value] }).to eq(41_501)
    expect(result[:recurring_total_cents]).to eq(1_062_000)
    expect(result[:contract_total_cents]).to eq(1_074_001)
  end

  it 'preserves the version 2 calculation for published historical terms' do
    result = JrcCrm::CommercialFinancials.new(attributes: attributes.merge(financial_version: 2), items: [monthly]).call
    expect(result).to include(financial_version: 2, total_cents: 29_500, contract_total_cents: 29_500)
    expect(result[:installment_plan_cents].sum).to eq(29_500)
    expect(result[:recurring_schedule][:count]).to eq(0)
  end

  it 'applies monthly item discounts to the fee and general discounts only to one-time charges' do
    result = JrcCrm::CommercialFinancials.new(attributes: attributes.merge(discount_cents: 1_000), items: [monthly.merge(discount_cents: 500)]).call
    expect(result).to include(monthly_cents: 29_000, recurring_total_cents: 1_044_000, total_cents: 28_000, discount_cents: 1_000,
                             contract_total_cents: 1_043_000, payable_base_cents: 0)
  end

  it 'keeps annual and usage initial-period semantics without inventing monthly charges for them' do
    annual = monthly.deep_merge(snapshot: { billing_model: 'annual' })
    usage = monthly.deep_merge(snapshot: { billing_model: 'usage' })
    result = JrcCrm::CommercialFinancials.new(attributes: attributes, items: [annual, usage]).call
    expect(result[:total_cents]).to eq(59_000)
    expect(result[:recurring_schedule][:count]).to eq(0)
    expect(result[:recurring_total_cents]).to eq(0)
  end

  it 'round-trips the new financial version and term through the order snapshot' do
    result = JrcCrm::CommercialFinancials.new(attributes: attributes, items: [monthly]).call
    snapshot = JrcCrm::OrderFinancials.snapshot_for(result)
    reloaded = JrcCrm::OrderFinancials.new(attributes: { snapshot: snapshot, installments_count: 36 }, items: result[:items]).call
    expect(reloaded.slice(:financial_version, :monthly_cents, :total_cents, :recurring_total_cents, :contract_total_cents))
      .to eq(result.slice(:financial_version, :monthly_cents, :total_cents, :recurring_total_cents, :contract_total_cents))
  end

  it 'rejects a fractional term instead of dividing or rounding a fee' do
    expect do
      JrcCrm::CommercialFinancials.new(attributes: attributes.merge(term_months: '36.5'), items: [monthly]).call
    end.to raise_error(JrcCrm::CommercialFinancials::InvalidTerms)
  end
end
