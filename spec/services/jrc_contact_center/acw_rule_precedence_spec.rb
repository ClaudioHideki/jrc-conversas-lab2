require 'rails_helper'

RSpec.describe JrcContactCenter::AcwRulePrecedence do
  let(:general) { { id: 'general', reason_code: 'order', scope: 'general', scope_id: nil, active: true, limit_seconds: 180 } }
  let(:team) { general.merge(id: 'team', scope: 'team', scope_id: 2, limit_seconds: 120) }
  let(:queue) { general.merge(id: 'queue', scope: 'queue', scope_id: 1, limit_seconds: 60) }
  let(:selector) { described_class.new(rules: [general, team, queue]) }

  it 'selects the queue rule above the team and general rules for the same reason' do
    result = selector.call(reason_code: 'order', queue_id: 1, team_ids: [2])
    expect(result).to include('id' => 'queue', 'limit_seconds' => 60, 'scope_id' => '1')
  end

  it 'selects a matching team above the general rule when no queue rule applies' do
    expect(selector.call(reason_code: 'order', queue_id: 9, team_ids: ['2'])).to include('id' => 'team', 'limit_seconds' => 120)
  end

  it 'selects the general rule when neither native queue nor team matches' do
    expect(selector.call(reason_code: 'order', queue_id: nil, team_ids: [])).to include('id' => 'general')
  end

  it 'returns no override for a different reason rather than inventing a limit or applying another classification' do
    expect(selector.call(reason_code: 'resolved', queue_id: 1, team_ids: [2])).to be_nil
  end

  it 'keeps an empty ruleset compatible with the native global snapshot path' do
    expect(described_class.new(rules: []).call(reason_code: 'order', queue_id: nil, team_ids: [])).to be_nil
  end

  it 'does not apply an inactive scoped rule' do
    policy = described_class.new(rules: [general, queue.merge(active: false)])
    expect(policy.call(reason_code: 'order', queue_id: 1, team_ids: [])).to include('id' => 'general')
  end

  it 'blocks duplicate matching queue rules without falling back to a team or general rule' do
    policy = described_class.new(rules: [general, team, queue, queue.merge(id: 'second')])
    expect { policy.call(reason_code: 'order', queue_id: 1, team_ids: [2]) }.to raise_error(described_class::Conflict) do |error|
      expect(error.level).to eq('queue')
    end
  end

  it 'blocks different applicable teams at the same level instead of choosing their order or shortest limit' do
    policy = described_class.new(rules: [general, team, team.merge(id: 'other_team', scope_id: 3, limit_seconds: 30)])
    expect { policy.call(reason_code: 'order', queue_id: nil, team_ids: [3, 2]) }.to raise_error(described_class::Conflict) do |error|
      expect(error.level).to eq('team')
    end
  end

  it 'blocks conflicting general rules when there is no higher applicable rule' do
    policy = described_class.new(rules: [general, general.merge(id: 'other')])
    expect { policy.call(reason_code: 'order', queue_id: nil, team_ids: []) }.to raise_error(described_class::Conflict)
  end

  it 'does not let an unrelated queue or team conflict affect an authorized higher scope choice' do
    policy = described_class.new(rules: [general, team, team.merge(id: 'other', scope_id: 3), queue])
    expect(policy.call(reason_code: 'order', queue_id: 1, team_ids: [2, 3])).to include('id' => 'queue')
  end

  [false, {}, { active: false }, { scope: 'unknown' }].each do |invalid|
    it "rejects malformed rule input #{invalid.inspect} rather than silently treating it as absent" do
      expect { described_class.new(rules: [invalid]) }.to raise_error(JrcContactCenter::OperationError, 'invalid_acw_rules')
    end
  end

  it 'does not mutate its original snapshot or expose a mutable reference to selected policy' do
    rules = [queue]
    policy = described_class.new(rules: rules)
    original = rules.deep_dup
    result = policy.call(reason_code: 'order', queue_id: 1, team_ids: [])
    result['limit_seconds'] = 300
    expect(rules).to eq(original)
    expect(policy.call(reason_code: 'order', queue_id: 1, team_ids: [])).to include('limit_seconds' => 60)
  end
end
