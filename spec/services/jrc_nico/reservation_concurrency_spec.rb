require 'rails_helper'

# Committed fixtures and row locks, exclusively in the opt-in disposable PostgreSQL database.
RSpec.describe 'NICO capacity concurrency', :sd_concurrency do
  self.use_transactional_tests = false
  include JrcServiceDeskConcurrency
  let!(:account) { create(:account, custom_attributes: { nico_concurrency: 1, nico_monthly_token_limit: 1000 }) }
  let!(:user) { create(:user, account: account) }

  around { |example| with_modified_env(NICO_MODE: 'provider') { example.run } }

  it 'admits only one simultaneous reservation using the real Account row lock' do
    account_id, user_id = account.id, user.id
    outcomes = concurrently(Array.new(2) do
      lambda do
        current = Account.find(account_id)
        current.with_lock do
          tokens = JrcNico::RunCapacity.reservation_for!(current, reservation_tokens: 100)
          JrcNico::Inference.create!(account: current, user_id: user_id, reserved_tokens: tokens).id
        end
      rescue JrcNico::RunCapacity::Exceeded => error
        error.code
      end
    end)
    expect(outcomes.count { |value| value.is_a?(Integer) }).to eq(1)
    expect(outcomes).to include('concurrency_limit')
    expect(JrcNico::Inference.where(account: account).count).to eq(1)
    expect(JrcNico::RunCapacity.snapshot(account)).to include(active_operations: 1, reserved_tokens: 100)
  end

  it 'serializes receipt recording and reconciliation without double counting or duplicate audit entries' do
    inference = JrcNico::Inference.create!(account: account, user: user, reserved_tokens: 1000)
    ledger = JrcNico::ReservationLedger.new(inference)
    ledger.prepare!(kind: 'operator')
    ledger.dispatched!
    inference.update!(lease_expires_at: 1.minute.ago)
    account_id, inference_id = account.id, inference.id
    receipt = { 'mode' => 'provider', 'model' => 'test-model', 'usage' => { 'input_tokens' => 20, 'output_tokens' => 10, 'total_tokens' => 30 } }
    operations = Array.new(2) { -> { JrcNico::ReservationLedger.new(JrcNico::Inference.find(inference_id)).receipt!(receipt); :receipt } }
    operations += Array.new(2) { -> { JrcNico::ReservationReconciler.new(account: Account.find(account_id)).call(dry_run: false); :reconciled } }
    expect(concurrently(operations)).to all(be_in(%i[receipt reconciled]))
    JrcNico::ReservationReconciler.new(account: account).call(dry_run: false)
    expect(account.jrc_ai_usage_events.count).to eq(1)
    expect(JrcNico::RunCapacity.snapshot(account)).to include(used_tokens: 30, reserved_tokens: 0, active_operations: 0)
    history = inference.reload.accounting['reconciliation_history'] || []
    expect(history.map { |entry| entry['classification'] }.uniq.size).to eq(history.size)
  end
end
