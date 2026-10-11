require 'rails_helper'

RSpec.describe 'Legacy NICO review concurrency', :sd_concurrency do
  self.use_transactional_tests = false
  include JrcServiceDeskConcurrency
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account: account, role: :administrator) }
  let!(:member) { account.account_users.find_by!(user: user) }
  let!(:record) { JrcNico::Inference.create!(account: account, user: user, status: 'unknown', reserved_tokens: 1000, created_at: 1.hour.ago) }
  let(:decision) do
    report = JrcNico::LegacyReservations.new(member: member)
    { 'request_id' => SecureRandom.uuid, 'fingerprint' => report.describe(record, 'inference')[:fingerprint], 'classification' => 'not_executed',
      'source' => 'runtime_not_executed', 'runtime_outcome' => 'not_dispatched',
      'justification' => 'Verified explicit non-dispatch evidence for this operation.',
      'excluded_usage_event_ids' => [], 'evidence' => [{ 'reference' => 'local-evidence', 'sha256' => Digest::SHA256.hexdigest('local evidence') }] }
  end

  it 'serializes identical approvals with one audit entry and one release' do
    input = decision
    token = JrcNico::LegacyReservationReview.new(member: member).call(type: 'inference', id: record.id, decision: input)['simulation_token']
    member_id, record_id = member.id, record.id
    outcomes = concurrently(Array.new(2) do
      lambda do
        JrcNico::LegacyReservationReview.new(member: AccountUser.find(member_id))
          .call(type: 'inference', id: record_id, decision: input, apply: true, authorized: true, simulation_token: token)
      end
    end)
    expect(outcomes).to all(be_a(Hash))
    expect(outcomes.count { |value| value['replayed'] == true }).to eq(1)
    expect(record.reload.reserved_tokens).to eq(0)
    expect(record.accounting['legacy_reviews'].size).to eq(1)
    expect(account.jrc_ai_usage_events.count).to eq(0)
  end

  it 'rejects the losing different decision after the first approval changes the snapshot' do
    inputs = [decision, decision.merge('request_id' => SecureRandom.uuid)]
    review = JrcNico::LegacyReservationReview.new(member: member)
    tokens = inputs.map { |input| review.call(type: 'inference', id: record.id, decision: input)['simulation_token'] }
    member_id, record_id = member.id, record.id
    outcomes = concurrently(inputs.zip(tokens).map do |input, token|
      lambda do
        JrcNico::LegacyReservationReview.new(member: AccountUser.find(member_id))
          .call(type: 'inference', id: record_id, decision: input, apply: true, authorized: true, simulation_token: token)
      end
    end)
    expect(outcomes.count { |value| value.is_a?(Hash) }).to eq(1)
    expect(outcomes.count { |value| value.is_a?(JrcNico::LegacyReservationReview::Conflict) }).to eq(1)
    expect(record.reload.accounting['legacy_reviews'].size).to eq(1)
    expect(record.reserved_tokens).to eq(0)
  end

  it 'prevents competing legacy records from associating the same previously unlinked event' do
    other = JrcNico::Inference.create!(account: account, user: user, status: 'unknown', reserved_tokens: 1000, created_at: record.created_at)
    event = JrcAi::UsageEvent.create!(account: account, user: user, agent_key: 'nico', feature: 'nico_operator', input_tokens: 30, total_tokens: 30,
                                     created_at: record.created_at, metadata: {})
    report = JrcNico::LegacyReservations.new(member: member)
    inputs = [record, other].map do |value|
      decision.merge('request_id' => SecureRandom.uuid, 'fingerprint' => report.describe(value, 'inference')[:fingerprint],
                     'classification' => 'confirmed', 'source' => 'recorded_usage', 'usage_event_ids' => [event.id])
    end
    review = JrcNico::LegacyReservationReview.new(member: member)
    tokens = inputs.zip([record, other]).map { |input, value| review.call(type: 'inference', id: value.id, decision: input)['simulation_token'] }
    member_id = member.id
    outcomes = concurrently(inputs.zip(tokens, [record.id, other.id]).map do |input, token, record_id|
      lambda do
        JrcNico::LegacyReservationReview.new(member: AccountUser.find(member_id))
          .call(type: 'inference', id: record_id, decision: input, apply: true, authorized: true, simulation_token: token)
      end
    end)
    expect(outcomes.count { |value| value.is_a?(Hash) }).to eq(1)
    expect(outcomes.count { |value| value.is_a?(JrcNico::LegacyReservationReview::Conflict) }).to eq(1)
    expect(account.jrc_ai_usage_events.count).to eq(1)
    expect([record, other].sum { |value| value.reload.reserved_tokens }).to eq(1000)
    expect(JrcNico::RunCapacity.snapshot(account)).to include(used_tokens: 30, reserved_tokens: 1000)
  end
end
