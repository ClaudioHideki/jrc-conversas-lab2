require 'rails_helper'

RSpec.describe JrcNico::LegacyReservationReview do
  let(:account) { create(:account, custom_attributes: { nico_monthly_token_limit: 2_000_000 }) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: user) }
  let(:record) { JrcNico::Inference.create!(account: account, user: user, status: 'unknown', reserved_tokens: 1000, created_at: 1.hour.ago) }
  let(:report) { JrcNico::LegacyReservations.new(member: member) }
  let(:review) { described_class.new(member: member) }
  let(:provider) do
    JrcAi::Provider.create!(account: account, name: 'Local test', provider_type: 'openai', default_model: 'test-model', api_key: 'test-only-key')
  end
  let(:evidence) { [{ 'reference' => 'review-local-001', 'sha256' => Digest::SHA256.hexdigest('local sanitized evidence') }] }
  let(:decision) do
    { 'request_id' => SecureRandom.uuid, 'fingerprint' => report.describe(record, 'inference')[:fingerprint],
      'classification' => 'unknown', 'source' => 'investigation', 'justification' => 'Reviewed the available evidence; outcome is still unknown.',
      'evidence' => evidence, 'excluded_usage_event_ids' => [] }
  end
  around { |example| travel_to(Time.zone.local(2026, 10, 11, 12)) { example.run } }

  # Simulation and application must use the same exact individual decision.
  def apply_decision(input = decision, current_record = record, type = 'inference')
    simulation = review.call(type: type, id: current_record.id, decision: input)
    review.call(type: type, id: current_record.id, decision: input, apply: true, authorized: true,
                simulation_token: simulation.fetch('simulation_token'))
  end

  it 'simulates without modifying reservations, history, usage or timestamps' do
    before = record.attributes
    result = review.call(type: 'inference', id: record.id, decision: decision)
    expect(result).to include('dry_run' => true, 'resulting_reserved_tokens' => 1000, 'new_usage_tokens' => 0)
    expect(record.reload.attributes).to eq(before)
    expect(account.jrc_ai_usage_events.count).to eq(0)
  end

  it 'keeps unknown usage reserved after explicit review and subsequent automatic reconciliation' do
    apply_decision
    JrcNico::ReservationReconciler.new(account: account).call(dry_run: false)
    expect(record.reload).to have_attributes(status: 'unknown', reserved_tokens: 1000)
    expect(record.accounting).to include('basis' => 'unknown')
    expect(record.accounting).not_to have_key('version')
    expect(record.accounting['legacy_reviews'].first).to include('actor_account_user_id' => member.id, 'explicitly_authorized' => true)
  end

  it 'requires explicit authorization even with a valid simulation' do
    input = decision
    simulation = review.call(type: 'inference', id: record.id, decision: input)
    expect do
      review.call(type: 'inference', id: record.id, decision: input, apply: true, simulation_token: simulation['simulation_token'])
    end.to raise_error(Pundit::NotAuthorizedError)
    expect(record.reload.reserved_tokens).to eq(1000)
  end

  it 'requires a signed unexpired simulation and rejects invented or expired tokens' do
    input = decision
    %w[invented invalid].each do |token|
      expect { review.call(type: 'inference', id: record.id, decision: input, apply: true, authorized: true, simulation_token: token) }
        .to raise_error(described_class::Conflict)
    end
    simulation = review.call(type: 'inference', id: record.id, decision: input)
    travel 16.minutes
    expect do
      review.call(type: 'inference', id: record.id, decision: input, apply: true, authorized: true, simulation_token: simulation['simulation_token'])
    end.to raise_error(described_class::Conflict)
  end

  it 'requires justification and a sanitized evidence reference with a SHA-256' do
    [{ 'justification' => '' }, { 'evidence' => [] }, { 'evidence' => [{ 'reference' => 'raw secret URL', 'sha256' => 'bad' }] }].each do |change|
      expect { review.call(type: 'inference', id: record.id, decision: decision.merge(change)) }.to raise_error(ArgumentError)
    end
  end

  it 'rejects credential-shaped evidence and unknown journal fields' do
    key = ['sk-', 'project', 'x' * 30].join
    [{ 'justification' => "Reviewed credential #{key}" }, { 'api_key' => 'do-not-store' }].each do |change|
      expect { review.call(type: 'inference', id: record.id, decision: decision.merge(change)) }.to raise_error(ArgumentError)
    end
    expect(record.reload.accounting).to eq({})
  end

  it 'refuses all new accounting versions and active legacy operations' do
    record.update!(accounting: { version: 1 })
    expect { review.call(type: 'inference', id: record.id, decision: decision) }.to raise_error(ArgumentError, 'new_accounting_record')
    record.update!(accounting: {}, status: 'running', lease_expires_at: 1.minute.from_now)
    input = decision.merge('fingerprint' => report.describe(record, 'inference')[:fingerprint])
    expect { review.call(type: 'inference', id: record.id, decision: input) }.to raise_error(described_class::Conflict, 'operation_still_active')
  end

  it 'rejects agents and a membership demoted after constructing the service' do
    input = decision
    review
    member.update!(role: :agent)
    expect { review.call(type: 'inference', id: record.id, decision: input) }.to raise_error(Pundit::NotAuthorizedError)
    expect { described_class.new(member: member) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rejects records and providers belonging to another account' do
    other = create(:account)
    foreign_user = create(:user, account: other)
    foreign = JrcNico::Inference.create!(account: other, user: foreign_user, reserved_tokens: 2000)
    expect { review.call(type: 'inference', id: foreign.id, decision: decision) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { report.describe(foreign, 'inference') }.to raise_error(Pundit::NotAuthorizedError)
    provider.update!(account: other)
    input = decision.merge('classification' => 'confirmed', 'source' => 'external_receipt', 'provider_id' => provider.id,
                           'model' => 'test-model', 'usage' => { 'input_tokens' => 20, 'output_tokens' => 10, 'total_tokens' => 30 })
    expect { review.call(type: 'inference', id: record.id, decision: input) }.to raise_error(ArgumentError, 'invalid_review_provider')
    expect(foreign.reload.reserved_tokens).to eq(2000)
  end

  it 'records confirmed external usage in the original period and releases only the reviewed reservation' do
    input = decision.merge('classification' => 'confirmed', 'source' => 'external_receipt', 'provider_id' => provider.id,
                           'model' => 'test-model', 'usage' => { 'input_tokens' => 20, 'output_tokens' => 10, 'total_tokens' => 30 })
    result = apply_decision(input)
    event = account.jrc_ai_usage_events.find(result['created_usage_event_id'])
    expect(event).to have_attributes(total_tokens: 30, created_at: record.created_at, provider_id: provider.id)
    expect(event.metadata).to include('administrative_attestation' => true, 'usage_estimated' => false, 'inference_id' => record.id)
    expect(record.reload).to have_attributes(status: 'failed', reserved_tokens: 0)
    expect(JrcNico::RunCapacity.snapshot(account)).to include(used_tokens: 30, reserved_tokens: 0, token_limit: 2_000_000)
  end

  it 'does not charge current month for a previous month reservation' do
    record.update!(created_at: Time.current.prev_month.beginning_of_month)
    input = decision.merge('classification' => 'confirmed', 'source' => 'external_receipt', 'provider_id' => provider.id,
                           'model' => 'test-model', 'usage' => { 'input_tokens' => 20, 'output_tokens' => 10, 'total_tokens' => 30 })
    apply_decision(input)
    expect(JrcNico::RunCapacity.snapshot(account)).to include(used_tokens: 0, reserved_tokens: 0)
    expect(report.report(period: record.created_at.strftime('%Y-%m'))).to include(count: 1, used_tokens: 30)
  end

  it 'reuses an already associated event without incrementing the accounted consumption' do
    event = JrcAi::UsageEvent.create!(account: account, user: user, agent_key: 'nico', feature: 'nico_operator',
                                     input_tokens: 20, output_tokens: 10, total_tokens: 30, created_at: record.created_at,
                                     metadata: { inference_id: record.id })
    input = decision.merge('classification' => 'confirmed', 'source' => 'recorded_usage', 'usage_event_ids' => [event.id])
    expect { apply_decision(input) }.not_to change(account.jrc_ai_usage_events, :count)
    expect(record.reload.reserved_tokens).to eq(0)
    expect(JrcNico::RunCapacity.snapshot(account)).to include(used_tokens: 30, reserved_tokens: 0)
  end

  it 'associates reviewed unlinked events without duplicate accounting and preserves metadata' do
    event = JrcAi::UsageEvent.create!(account: account, user: user, agent_key: 'nico', feature: 'nico_operator',
                                     input_tokens: 20, output_tokens: 10, total_tokens: 30, created_at: record.created_at,
                                     metadata: { retained: true })
    input = decision.merge('classification' => 'confirmed', 'source' => 'recorded_usage', 'usage_event_ids' => [event.id])
    expect { apply_decision(input) }.not_to change(account.jrc_ai_usage_events, :count)
    expect(event.reload.metadata).to include('retained' => true, 'inference_id' => record.id)
  end

  it 'requires review of every candidate before recording fresh usage or non-execution' do
    event = JrcAi::UsageEvent.create!(account: account, user: user, agent_key: 'nico', feature: 'nico_operator',
                                     input_tokens: 20, total_tokens: 20, created_at: record.created_at, metadata: {})
    expect(report.describe(record, 'inference')[:candidate_usage_events].first).to include(id: event.id, correlation: 'candidate_only_not_proof')
    expect { review.call(type: 'inference', id: record.id, decision: decision) }.to raise_error(ArgumentError, 'candidate_events_require_review')
    apply_decision(decision.merge('excluded_usage_event_ids' => [event.id]))
    expect(record.reload.reserved_tokens).to eq(1000)
  end

  it 'refuses receipts associated to another reservation or account, and copilot receipts' do
    foreign = create(:account)
    events = [
      JrcAi::UsageEvent.create!(account: foreign, agent_key: 'nico', feature: 'nico_operator', input_tokens: 30, total_tokens: 30, metadata: {}),
      JrcAi::UsageEvent.create!(account: account, user: user, agent_key: 'copilot', feature: 'assistant',
                               input_tokens: 30, total_tokens: 30, metadata: {}),
      JrcAi::UsageEvent.create!(account: account, user: user, agent_key: 'nico', feature: 'nico_operator', input_tokens: 30, total_tokens: 30,
                               created_at: record.created_at, metadata: { inference_id: record.id + 1 })
    ]
    events.each do |event|
      input = decision.merge('classification' => 'confirmed', 'source' => 'recorded_usage', 'usage_event_ids' => [event.id])
      error_class = event == events.last ? described_class::Conflict : ArgumentError
      expect { review.call(type: 'inference', id: record.id, decision: input) }.to raise_error(error_class)
    end
    expect(record.reload.reserved_tokens).to eq(1000)
  end

  it 'rejects duplicate, incomplete and invalid receipt totals' do
    event = JrcAi::UsageEvent.create!(account: account, user: user, agent_key: 'nico', feature: 'nico_operator', total_tokens: 30,
                                     created_at: record.created_at, metadata: { inference_id: record.id })
    [[], [event.id, event.id], [event.id]].each do |ids|
      input = decision.merge('classification' => 'confirmed', 'source' => 'recorded_usage', 'usage_event_ids' => ids)
      expect { review.call(type: 'inference', id: record.id, decision: input) }.to raise_error(ArgumentError)
    end
  end

  it 'retains estimation labels and refuses a confirmed classification for an estimated event' do
    event = JrcAi::UsageEvent.create!(account: account, user: user, agent_key: 'nico', feature: 'nico_operator', input_tokens: 30, total_tokens: 30,
                                     created_at: record.created_at, metadata: { inference_id: record.id, usage_estimated: true })
    input = decision.merge('classification' => 'confirmed', 'source' => 'recorded_usage', 'usage_event_ids' => [event.id])
    expect { review.call(type: 'inference', id: record.id, decision: input) }.to raise_error(ArgumentError, 'receipt_classification_mismatch')
    apply_decision(input.merge('classification' => 'estimated'))
    expect(record.reload.accounting['basis']).to eq('estimated')
  end

  it 'never lowers an unknown bound using an unproven or insufficient estimate' do
    input = decision.merge('classification' => 'estimated', 'source' => 'conservative_estimate', 'provider_id' => provider.id,
                           'model' => 'test-model', 'usage' => { 'input_tokens' => 900, 'output_tokens' => 100, 'total_tokens' => 1000 })
    expect { review.call(type: 'inference', id: record.id, decision: input) }.to raise_error(ArgumentError, 'conservative_estimate_required')
    small = input.merge('conservative_upper_bound' => true, 'usage' => { 'input_tokens' => 20, 'output_tokens' => 10, 'total_tokens' => 30 })
    expect { review.call(type: 'inference', id: record.id, decision: small) }.to raise_error(ArgumentError, 'estimate_cannot_lower_unknown_bound')
    apply_decision(input.merge('conservative_upper_bound' => true))
    expect(JrcNico::RunCapacity.snapshot(account)).to include(used_tokens: 1000, reserved_tokens: 0)
    expect(account.jrc_ai_usage_events.first.metadata['usage_estimated']).to be(true)
  end

  it 'requires affirmative proof of non-execution instead of an absent receipt' do
    input = decision.merge('classification' => 'not_executed', 'source' => 'runtime_not_executed')
    expect { review.call(type: 'inference', id: record.id, decision: input) }.to raise_error(ArgumentError, 'non_execution_proof_required')
    apply_decision(input.merge('runtime_outcome' => 'rejected_before_provider'))
    expect(record.reload).to have_attributes(status: 'failed', reserved_tokens: 0)
    expect(account.jrc_ai_usage_events.count).to eq(0)
    expect(JrcNico::RunCapacity.snapshot(account)).to include(used_tokens: 0, executions: 0)
  end

  it 'refuses non-execution or fresh accounting when usage is already associated' do
    JrcAi::UsageEvent.create!(account: account, agent_key: 'nico', feature: 'nico_operator', input_tokens: 30, total_tokens: 30,
                             created_at: record.created_at, metadata: { inference_id: record.id })
    input = decision.merge('classification' => 'not_executed', 'source' => 'runtime_not_executed', 'runtime_outcome' => 'not_dispatched')
    expect { review.call(type: 'inference', id: record.id, decision: input) }.to raise_error(described_class::Conflict, 'usage_already_recorded')
  end

  it 'preserves existing history including previous reconciliation entries before reviewing again' do
    history = [{ 'classification' => 'abandoned_unknown' }, { 'classification' => 'uncertain_manual_review' }]
    record.update!(accounting: { reconciliation_history: history, retained: true })
    apply_decision
    expect(record.reload.accounting['reconciliation_history'].first(2)).to eq(history)
    expect(record.accounting['retained']).to be(true)
    expect(record.accounting['reconciliation_history'].size).to eq(3)
  end

  it 'makes identical retry idempotent, even when JSON key order differs, without a second audit' do
    input = decision
    original = apply_decision(input)
    before = record.reload.attributes
    repeated = review.call(type: 'inference', id: record.id, decision: input.to_a.reverse.to_h, apply: true, authorized: true)
    expect(repeated).to eq(original.merge('replayed' => true))
    expect(record.reload.attributes).to eq(before)
    expect do
      review.call(type: 'inference', id: record.id, decision: input, apply: true)
    end.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rejects idempotency key reuse for changed decisions and other records' do
    input = decision
    apply_decision(input)
    expect do
      review.call(type: 'inference', id: record.id, decision: input.merge('justification' => 'A different administrative decision.'),
                  apply: true, authorized: true)
    end.to raise_error(described_class::Conflict, 'review_request_conflict')
    other = JrcNico::Inference.create!(account: account, user: user, status: 'unknown', reserved_tokens: 1000, created_at: 1.hour.ago)
    expect { review.call(type: 'inference', id: other.id, decision: input, apply: true, authorized: true) }
      .to raise_error(described_class::Conflict, 'review_request_conflict')
  end

  it 'requires a fresh snapshot after a reservation changes' do
    input = decision
    record.update!(reserved_tokens: 2000)
    expect { apply_decision(input) }.to raise_error(described_class::Conflict, 'review_snapshot_changed')
  end

  it 'detects an event changed after simulation even when it was not a time-window candidate' do
    event = JrcAi::UsageEvent.create!(account: account, user: user, agent_key: 'nico', feature: 'nico_operator', input_tokens: 30, total_tokens: 30,
                                     created_at: record.created_at + 10.minutes, metadata: {})
    input = decision.merge('classification' => 'confirmed', 'source' => 'recorded_usage', 'usage_event_ids' => [event.id])
    simulation = review.call(type: 'inference', id: record.id, decision: input)
    event.update!(input_tokens: 40, total_tokens: 40)
    expect do
      review.call(type: 'inference', id: record.id, decision: input, apply: true, authorized: true, simulation_token: simulation['simulation_token'])
    end.to raise_error(described_class::Conflict, 'review_simulation_required_or_changed')
    expect(record.reload.reserved_tokens).to eq(1000)
  end

  it 'rolls back event creation if saving the reservation fails' do
    input = decision.merge('classification' => 'confirmed', 'source' => 'external_receipt', 'provider_id' => provider.id,
                           'model' => 'test-model', 'usage' => { 'input_tokens' => 20, 'output_tokens' => 10, 'total_tokens' => 30 })
    allow_any_instance_of(JrcNico::Inference).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)
    expect { apply_decision(input) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(account.jrc_ai_usage_events.count).to eq(0)
    expect(record.reload.reserved_tokens).to eq(1000)
  end

  it 'does not reinterpret already settled legacy decisions' do
    input = decision.merge('classification' => 'not_executed', 'source' => 'runtime_not_executed', 'runtime_outcome' => 'not_dispatched')
    apply_decision(input)
    next_decision = decision.merge('request_id' => SecureRandom.uuid, 'fingerprint' => report.describe(record.reload, 'inference')[:fingerprint])
    expect { apply_decision(next_decision) }
      .to raise_error(described_class::Conflict, 'legacy_review_already_settled')
  end

  it 'supports legacy runs and requires association of exact request-ID receipts' do
    run = JrcNico::Run.create!(account: account, user: user, conversation: create(:conversation, account: account),
                              request_id: SecureRandom.uuid, message: 'Local test', status: 'failed', reserved_tokens: 1000, created_at: 1.hour.ago)
    event = JrcAi::UsageEvent.create!(account: account, user: user, agent_key: 'nico', feature: 'assisted_analysis',
                                     input_tokens: 30, total_tokens: 30,
                                     created_at: run.created_at + 10.minutes, metadata: { request_id: run.request_id })
    input = decision.merge('fingerprint' => report.describe(run, 'run')[:fingerprint], 'excluded_usage_event_ids' => [event.id])
    expect { review.call(type: 'run', id: run.id, decision: input) }.to raise_error(described_class::Conflict, 'request_usage_requires_association')
    input = input.merge('classification' => 'confirmed', 'source' => 'recorded_usage', 'usage_event_ids' => [event.id])
    apply_decision(input, run, 'run')
    expect(run.reload.reserved_tokens).to eq(0)
    expect(event.reload.metadata['run_id']).to eq(run.id)
  end

  it 'reports legacy rows separately from versioned operations by account and period' do
    record
    JrcNico::Inference.create!(account: account, user: user, reserved_tokens: 2000, accounting: { version: 1 })
    before = record.attributes
    result = report.report(period: record.created_at.strftime('%Y-%m'))
    expect(result).to include(count: 1, legacy_reserved_tokens: 1000, classified: { 'unknown' => 1 }, dry_run: true)
    expect(result[:records].first).to include(legacy: true, automatically_releasable: false, request_id: nil)
    expect(record.reload.attributes).to eq(before)
    expect { report.report(period: '2026-13') }.to raise_error(ArgumentError)
  end

  it 'keeps fingerprints stable across JSONB key ordering while still detecting real state changes' do
    record.update!(accounting: { retained: true, reconciliation_history: [{ classification: 'unknown', actor: 'system' }] })
    initial = report.describe(record, 'inference')[:fingerprint]
    expect(report.describe(record.reload, 'inference')[:fingerprint]).to eq(initial)
    record.update!(reserved_tokens: 2000)
    expect(report.describe(record.reload, 'inference')[:fingerprint]).not_to eq(initial)
  end

  it 'rejects zero, negative, fractional, oversized and inconsistent external usage without writing a receipt' do
    input = decision.merge('classification' => 'confirmed', 'source' => 'external_receipt', 'provider_id' => provider.id, 'model' => 'test-model')
    invalid = [
      { 'input_tokens' => 0, 'output_tokens' => 0, 'total_tokens' => 0 },
      { 'input_tokens' => -1, 'output_tokens' => 2, 'total_tokens' => 1 },
      { 'input_tokens' => 1.5, 'output_tokens' => 1.5, 'total_tokens' => 3 },
      { 'input_tokens' => 270_001, 'output_tokens' => 0, 'total_tokens' => 270_001 },
      { 'input_tokens' => 20, 'output_tokens' => 10, 'total_tokens' => 31 }
    ]
    invalid.each do |usage|
      expect { review.call(type: 'inference', id: record.id, decision: input.merge('usage' => usage)) }
        .to raise_error(ArgumentError, 'invalid_review_usage')
    end
    expect(account.jrc_ai_usage_events.count).to eq(0)
    expect(record.reload.reserved_tokens).to eq(1000)
  end

  it 'permits a later evidence-backed decision after an unknown review while retaining both audits' do
    apply_decision
    input = decision.merge('request_id' => SecureRandom.uuid, 'fingerprint' => report.describe(record.reload, 'inference')[:fingerprint],
                           'classification' => 'confirmed', 'source' => 'external_receipt', 'provider_id' => provider.id,
                           'model' => 'test-model', 'usage' => { 'input_tokens' => 20, 'output_tokens' => 10, 'total_tokens' => 30 })
    apply_decision(input)
    expect(record.reload.reserved_tokens).to eq(0)
    expect(record.accounting['legacy_reviews'].map { |entry| entry['classification'] }).to eq(%w[unknown confirmed])
    expect(record.accounting['reconciliation_history'].size).to eq(2)
    expect(account.jrc_ai_usage_events.count).to eq(1)
  end
end
