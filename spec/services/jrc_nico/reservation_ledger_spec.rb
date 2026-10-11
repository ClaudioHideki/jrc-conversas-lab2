require 'rails_helper'

RSpec.describe JrcNico::ReservationLedger do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:provider) do
    JrcAi::Provider.create!(account: account, name: 'Test', provider_type: 'openai', default_model: 'test-model',
                           api_key: 'test-key-not-real', active: true, default_provider: true)
  end
  let(:inference) { JrcNico::Inference.create!(account: account, user: user, reserved_tokens: 1000) }
  let(:ledger) { described_class.new(inference) }
  let(:result) { { 'mode' => 'provider', 'model' => 'test-model', 'usage' => { 'input_tokens' => 20, 'output_tokens' => 10, 'total_tokens' => 30 } } }

  before { ledger.prepare!(kind: 'operator', provider: provider) }

  it 'completes atomically with one account-owned receipt and no duplicate consumption on retry' do
    ledger.dispatched!
    ledger.complete!(result)
    before = inference.reload.attributes
    ledger.complete!(result)
    expect(inference.reload.attributes).to eq(before)
    expect(inference.reload).to have_attributes(status: 'completed', reserved_tokens: 0)
    expect(ledger.events.count).to eq(1)
    expect(ledger.events.first).to have_attributes(account_id: account.id, user_id: user.id, provider_id: provider.id, total_tokens: 30)
    expect(JrcNico::RunCapacity.snapshot(account)).to include(used_tokens: 30, reserved_tokens: 0, executions: 1)
  end

  it 'releases a failure proven to precede dispatch without recording fabricated usage' do
    ledger.failed!(JrcNico::RuntimeClient::Error.new('invalid_configuration'))
    expect(inference.reload).to have_attributes(status: 'failed', reserved_tokens: 0)
    expect(inference.accounting['basis']).to eq('not_executed')
    expect(ledger.events).to be_empty
    expect(JrcNico::RunCapacity.snapshot(account)[:executions]).to eq(0)
  end

  it 'retains the bound on timeout after dispatch and does not count it as a live slot' do
    ledger.dispatched!
    ledger.failed!(JrcNico::RuntimeClient::Error.new('runtime_timeout'))
    expect(inference.reload).to have_attributes(status: 'unknown', reserved_tokens: 1000)
    expect(inference.accounting['basis']).to eq('unknown')
    expect(ledger.events).to be_empty
    expect(JrcNico::RunCapacity.snapshot(account)).to include(active_operations: 0, uncertain_tokens: 1000, executions: 1)
  end

  it 'preserves a known receipt when output validation fails afterward' do
    ledger.dispatched!
    ledger.receipt!(result)
    ledger.failed!(JrcNico::RuntimeClient::Error.new('tool_arguments_invalid'))
    expect(inference.reload).to have_attributes(status: 'failed', reserved_tokens: 0)
    expect(inference.accounting['basis']).to eq('confirmed')
    expect(ledger.events.sum(:total_tokens)).to eq(30)
  end

  it 'labels estimated usage explicitly and keeps it counted' do
    ledger.complete!(result.merge('usage_estimated' => true))
    expect(inference.reload.accounting['basis']).to eq('estimated')
    expect(ledger.events.first.metadata).to include('usage_estimated' => true, 'cost_available' => false)
    expect(JrcNico::RunCapacity.snapshot(account)[:used_tokens]).to eq(30)
  end

  it 'does not silently accept conflicting receipts or malformed estimation markers' do
    ledger.receipt!(result)
    expect { ledger.receipt!(result.merge('usage' => { 'input_tokens' => 21, 'output_tokens' => 10, 'total_tokens' => 31 })) }
      .to raise_error(JrcNico::RuntimeClient::Error, 'provider_usage_invalid')
    expect { ledger.receipt!(result.merge('usage_estimated' => 'true')) }.to raise_error(JrcNico::RuntimeClient::Error)
    expect(ledger.events.sum(:total_tokens)).to eq(30)
  end

  it 'pins late receipts to the original reservation month' do
    inference.update!(created_at: Time.current.prev_month.beginning_of_month)
    ledger.receipt!(result)
    expect(ledger.events.first.created_at).to eq(inference.created_at)
    expect(JrcNico::RunCapacity.snapshot(account)).to include(used_tokens: 0, reserved_tokens: 0)
  end

  it 'rejects a provider belonging to another account' do
    other = create(:account)
    foreign = JrcAi::Provider.create!(account: other, name: 'Foreign', provider_type: 'openai', default_model: 'test-model', api_key: 'test-foreign-key')
    expect { ledger.prepare!(kind: 'operator', provider: foreign) }.to raise_error(JrcNico::RuntimeClient::Error, 'invalid_scope')
    expect(inference.reload.accounting['provider_id']).to eq(provider.id)
  end

  it 'refuses dispatch after the lease expires even if a worker resumes' do
    inference.update!(lease_expires_at: 1.second.ago)
    expect { ledger.dispatched! }.to raise_error(JrcNico::RuntimeClient::Error, 'request_cancelled')
    expect(inference.reload.accounting).not_to have_key('dispatch_started_at')
  end

  it 'never stores prompt, credential or exception text in the audit journal' do
    ledger.failed!(StandardError.new('PRIVATE-SECRET-PROMPT'))
    expect(inference.reload.accounting.to_json).not_to include('PRIVATE', 'test-key-not-real')
  end
end
