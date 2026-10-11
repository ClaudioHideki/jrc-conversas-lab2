require 'rails_helper'

RSpec.describe JrcNico::ReservationReconciler do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:inference) { JrcNico::Inference.create!(account: account, user: user, status: 'running', reserved_tokens: 1000, created_at: 5.minutes.ago) }
  let(:reconciler) { described_class.new(account: account) }

  it 'defaults to diagnosis without modifying any timestamp, status or reservation' do
    before = inference.attributes
    expect(reconciler.call.first).to include(classification: 'abandoned_unknown', release_tokens: false)
    expect(inference.reload.attributes).to eq(before)
  end

  it 'marks an abandoned legacy operation unknown, retains its full bound and is idempotent' do
    inference
    reconciler.call(dry_run: false)
    expect(inference.reload).to have_attributes(status: 'unknown', reserved_tokens: 1000)
    before = inference.attributes
    2.times { reconciler.call(dry_run: false) }
    expect(inference.reload.attributes).to eq(before)
    expect(inference.accounting['reconciliation_history'].size).to eq(1)
  end

  it 'never clears old unknown reservations, even from a previous month' do
    inference.update!(status: 'unknown', created_at: Time.current.prev_month.beginning_of_month)
    before = inference.attributes
    expect(reconciler.call.first).to include(classification: 'uncertain_manual_review', release_tokens: false)
    reconciler.call(dry_run: false)
    expect(inference.reload.attributes).to eq(before)
  end

  it 'safely frees an expired operation that has a persisted proof of no dispatch' do
    ledger = JrcNico::ReservationLedger.new(inference)
    ledger.prepare!(kind: 'operator')
    inference.update!(lease_expires_at: 1.minute.ago)
    expect(reconciler.call.first).to include(classification: 'expired_not_dispatched', release_tokens: true)
    reconciler.call(dry_run: false)
    expect(inference.reload).to have_attributes(status: 'failed', reserved_tokens: 0)
    expect(inference.accounting).to include('basis' => 'not_executed')
    expect(ledger.events).to be_empty
    expect { ledger.dispatched! }.to raise_error(JrcNico::RuntimeClient::Error, 'request_cancelled')
  end

  it 'preserves uncertainty after an interrupted dispatched operation, without automatically retrying it' do
    ledger = JrcNico::ReservationLedger.new(inference)
    ledger.prepare!(kind: 'operator')
    ledger.dispatched!
    inference.update!(lease_expires_at: 1.minute.ago)
    expect { reconciler.call(dry_run: false) }.not_to have_enqueued_job
    expect(inference.reload).to have_attributes(status: 'unknown', reserved_tokens: 1000)
  end

  it 'deduplicates an already recorded receipt and never fabricates completion' do
    inference.update!(status: 'unknown')
    JrcAi::UsageEvent.create!(account: account, user: user, agent_key: 'nico', feature: 'nico_operator',
                             total_tokens: 30, input_tokens: 20, output_tokens: 10, metadata: { inference_id: inference.id })
    expect(JrcNico::RunCapacity.snapshot(account)).to include(used_tokens: 30, reserved_tokens: 0)
    reconciler.call(dry_run: false)
    expect(inference.reload).to have_attributes(status: 'failed', reserved_tokens: 0)
    expect(inference.accounting['reconciliation']).to include('classification' => 'usage_already_recorded', 'previous_reserved_tokens' => 1000)
    expect(account.jrc_ai_usage_events.count).to eq(1)
  end

  it 'ignores a forged receipt correlation in a different account' do
    other = create(:account)
    inference.update!(status: 'unknown')
    JrcAi::UsageEvent.create!(account: other, agent_key: 'nico', feature: 'nico_operator', total_tokens: 30, metadata: { inference_id: inference.id })
    reconciler.call(dry_run: false)
    expect(inference.reload.reserved_tokens).to eq(1000)
    expect(JrcNico::RunCapacity.snapshot(account)).to include(used_tokens: 0, reserved_tokens: 1000)
  end

  it 'preserves the estimation label when reconciling an already counted conservative receipt' do
    inference.update!(status: 'unknown')
    JrcAi::UsageEvent.create!(account: account, agent_key: 'nico', feature: 'nico_operator', total_tokens: 30,
                             metadata: { inference_id: inference.id, usage_estimated: true })
    reconciler.call(dry_run: false)
    expect(inference.reload).to have_attributes(status: 'failed', reserved_tokens: 0)
    expect(inference.accounting['basis']).to eq('estimated')
    expect(JrcNico::RunCapacity.snapshot(account)).to include(used_tokens: 30, reserved_tokens: 0)
  end

  it 'never touches another account reservation or accepts a copilot correlation as a NICO receipt' do
    foreign_account = create(:account)
    foreign_user = create(:user, account: foreign_account)
    foreign = JrcNico::Inference.create!(account: foreign_account, user: foreign_user, reserved_tokens: 5000, created_at: 1.day.ago)
    before = foreign.attributes
    inference.update!(status: 'unknown')
    JrcAi::UsageEvent.create!(account: account, agent_key: 'copilot', feature: 'assistant', total_tokens: 30, metadata: { inference_id: inference.id })
    reconciler.call(dry_run: false)
    expect(foreign.reload.attributes).to eq(before)
    expect(inference.reload.reserved_tokens).to eq(1000)
  end

  it 'expires a never-started queued run without sending it or resurrecting it' do
    run = JrcNico::Run.create!(account: account, user: user, conversation: create(:conversation, account: account),
                             request_id: SecureRandom.uuid, message: 'Local test', reserved_tokens: 2000, created_at: 20.minutes.ago)
    reconciler.call(dry_run: false)
    expect(run.reload).to have_attributes(status: 'cancelled', reserved_tokens: 0, error_code: 'queue_expired_not_executed')
    expect(JrcNico::RuntimeClient).not_to receive(:new)
    JrcNico::AnalyzeJob.perform_now(run.id)
    expect(run.reload.status).to eq('cancelled')
  end

  it 'preserves earlier audit entries when a later receipt reconciles an unknown operation' do
    inference
    reconciler.call(dry_run: false)
    JrcAi::UsageEvent.create!(account: account, agent_key: 'nico', feature: 'nico_operator', total_tokens: 30, metadata: { inference_id: inference.id })
    reconciler.call(dry_run: false)
    expect(inference.reload.accounting['reconciliation_history'].map { |row| row['classification'] })
      .to eq(%w[abandoned_unknown usage_already_recorded])
  end
end
