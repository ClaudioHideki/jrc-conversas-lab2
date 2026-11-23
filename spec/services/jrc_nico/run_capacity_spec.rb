require 'rails_helper'

RSpec.describe JrcNico::RunCapacity do
  let(:account) { create(:account, custom_attributes: { nico_monthly_token_limit: 1000, nico_monthly_run_limit: 10, nico_concurrency: 2 }) }
  let(:user) { create(:user, account: account) }
  around { |example| with_modified_env(NICO_MODE: 'provider') { example.run } }

  it 'enforces legitimate monthly usage without changing the configured limits' do
    JrcAi::UsageEvent.create!(account: account, agent_key: 'nico', feature: 'nico_operator', total_tokens: 950)
    expect { account.with_lock { described_class.reservation_for!(account, reservation_tokens: 100) } }
      .to raise_error(described_class::Exceeded) { |error| expect(error.code).to eq('monthly_token_limit') }
    expect(account.reload.custom_attributes['nico_monthly_token_limit']).to eq(1000)
  end

  it 'distinguishes unknown reservations from a real usage limit and retains the bound' do
    record = JrcNico::Inference.create!(account: account, user: user, status: 'unknown', reserved_tokens: 950)
    expect { account.with_lock { described_class.reservation_for!(account, reservation_tokens: 100) } }
      .to raise_error(described_class::Exceeded) { |error| expect(error.code).to eq('reservation_reconciliation_required') }
    expect(record.reload.reserved_tokens).to eq(950)
  end

  it 'recovers false blocking from a provably undispatched stale operation before admitting work' do
    record = JrcNico::Inference.create!(account: account, user: user, reserved_tokens: 950)
    JrcNico::ReservationLedger.new(record).prepare!(kind: 'operator')
    record.update!(lease_expires_at: 1.minute.ago)
    expect(account.with_lock { described_class.reservation_for!(account, reservation_tokens: 100) }).to eq(100)
    expect(record.reload).to have_attributes(status: 'failed', reserved_tokens: 0)
  end

  it 'does not charge another account usage or prior-month unknown holds to this month' do
    other = create(:account)
    JrcAi::UsageEvent.create!(account: other, agent_key: 'nico', feature: 'nico_operator', total_tokens: 200_000)
    record = JrcNico::Inference.create!(account: account, user: user, status: 'unknown', reserved_tokens: 270_000,
                                      created_at: Time.current.prev_month.beginning_of_month)
    expect(described_class.snapshot(account)).to include(token_limit: 1000, used_tokens: 0, reserved_tokens: 0, executions: 0)
    expect(account.with_lock { described_class.reservation_for!(account, reservation_tokens: 100) }).to eq(100)
    expect(record.reload.reserved_tokens).to eq(270_000)
  end

  it 'distinguishes execution and live concurrency limits' do
    account.update!(custom_attributes: account.custom_attributes.merge('nico_monthly_run_limit' => 0))
    expect { account.with_lock { described_class.reservation_for!(account) } }
      .to raise_error(described_class::Exceeded) { |error| expect(error.code).to eq('monthly_execution_limit') }
    account.update!(custom_attributes: account.custom_attributes.merge('nico_monthly_run_limit' => 10))
    2.times { JrcNico::Inference.create!(account: account, user: user) }
    expect { account.with_lock { described_class.reservation_for!(account) } }
      .to raise_error(described_class::Exceeded) { |error| expect(error.code).to eq('concurrency_limit') }
  end

  context 'provider-managed consumption' do
    let!(:provider) do
      JrcAi::Provider.create!(account: account, name: 'Provider account', provider_type: 'custom',
                              api_key: 'test-key-only', base_url: 'https://api.groq.com/openai', default_model: 'test-model',
                              settings: { usage_policy: 'provider' }, monthly_token_limit: 1)
    end

    it 'admits work using provider limits while retaining unknown usage as audit evidence' do
      record = JrcNico::Inference.create!(account: account, user: user, status: 'unknown', reserved_tokens: 950)
      JrcAi::UsageEvent.create!(account: account, agent_key: 'nico', feature: 'nico_operator', total_tokens: 950)
      expect(account.with_lock { described_class.reservation_for!(account, reservation_tokens: 100) }).to eq(100)
      expect(described_class.snapshot(account)).to include(limit_source: 'provider', token_limit: nil, execution_limit: nil,
                                                         remaining_tokens: nil, used_tokens: 950, uncertain_tokens: 950)
      expect(record.reload.reserved_tokens).to eq(950)
      expect(account.reload.custom_attributes['nico_monthly_token_limit']).to eq(1000)
    end

    it 'still enforces live concurrency and conversation isolation' do
      2.times { JrcNico::Inference.create!(account: account, user: user) }
      expect { account.with_lock { described_class.reservation_for!(account) } }
        .to raise_error(described_class::Exceeded) { |error| expect(error.code).to eq('concurrency_limit') }
    end

    it 'retains local policy and bounds in a different account' do
      other = create(:account, custom_attributes: { nico_monthly_token_limit: 0 })
      expect { other.with_lock { described_class.reservation_for!(other, reservation_tokens: 1) } }
        .to raise_error(described_class::Exceeded) { |error| expect(error.code).to eq('monthly_token_limit') }
    end

    it 'applies an explicitly selected local provider ceiling' do
      provider.update!(settings: { usage_policy: 'local' }, monthly_token_limit: 0)
      expect { account.with_lock { described_class.reservation_for!(account, reservation_tokens: 1) } }
        .to raise_error(described_class::Exceeded) { |error| expect(error.code).to eq('monthly_token_limit') }
    end
  end

end
