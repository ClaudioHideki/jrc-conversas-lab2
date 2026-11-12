require 'rails_helper'

RSpec.describe JrcRelationship::HealthChange do
  it 'does not report a source change caused only by JSON string keys in an immutable stored observation' do
    factor = { factor: 'satisfaction', contribution: 20, measurement: { state: 'current', observed_at: '2026-11-01T12:00:00Z' } }
    previous = { score: 20, factors: [factor.deep_stringify_keys] }
    current = { score: 20, factors: [factor] }
    original = previous.deep_dup
    expect(described_class.call(previous: previous, current: current)).to include(delta: 0, factors: [])
    expect(previous).to eq(original)
  end

  it 'preserves the actual changed measurement and score explanation across serialized snapshots' do
    before = { factor: 'satisfaction', contribution: 20, measurement: { state: 'current', window_days: 90 } }
    after = { factor: 'satisfaction', contribution: 10, measurement: { state: 'current', window_days: 14 } }
    result = described_class.call(previous: { score: 20, factors: [before.deep_stringify_keys] }, current: { score: 10, factors: [after] })
    expect(result[:factors].first).to include(delta: -10, before: { contribution: 20, measurement: before[:measurement] },
                                              after: { contribution: 10, measurement: after[:measurement] })
  end
end
