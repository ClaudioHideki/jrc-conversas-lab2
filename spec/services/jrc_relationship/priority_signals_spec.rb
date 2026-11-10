require 'rails_helper'

RSpec.describe JrcRelationship::PrioritySignals do
  let(:rules) { JrcRelationship::Configuration::DEFAULT_RULES }
  let(:data) { { health: { score: 100 }, mrr_cents: 0, renewal_on: Date.current + 120, days_without_contact: 0 } }

  it 'leaves legacy factors unchanged unless explicitly enabled, including older saved rule sets' do
    legacy = rules.except(*described_class::RULES)
    expect(described_class.call(data, legacy)).to eq({})
    expect(JrcRelationship::Priority.call(data: data, rules: legacy, kind: 'health')).to eq(
      JrcRelationship::Priority.call(data: data, rules: rules, kind: 'health')
    )
  end

  it 'uses actual observed score movement and authorized SLA evidence with configured relative weights' do
    configured = rules.merge('priority_trend' => 1, 'priority_sla' => 1)
    observed = data.merge(health_change: { drop: 25, snapshot_id: 123 }, sla_breached: 2)
    result = JrcRelationship::Priority.call(data: observed, rules: configured, kind: 'health')
    expect(result[:score]).to eq(42)
    expect(result[:factors]['trend']).to include(normalized: 25, source_snapshot_id: 123, raw_drop_points: 25, available: true)
    expect(result[:factors]['sla']).to include(normalized: 100, breached_count: 2, available: true)
  end

  it 'distinguishes unavailable evidence from observed recovery and zero breached tickets' do
    configured = rules.merge('priority_trend' => 1, 'priority_sla' => 1)
    missing = JrcRelationship::Priority.call(data: data, rules: configured, kind: 'health')
    actual = JrcRelationship::Priority.call(data: data.merge(health_change: { drop: -20 }, sla_breached: 0), rules: configured, kind: 'health')
    expect(missing[:factors].values_at('trend', 'sla')).to all(include(normalized: nil, available: false, contribution: nil))
    expect(actual[:factors].values_at('trend', 'sla')).to all(include(normalized: 0, available: true, contribution: 0.0))
  end

  it 'retains explicit manual priority and configured critical urgency evidence without rewriting past actions' do
    configured = rules.merge('priority_trend' => 1, 'priority_sla' => 1)
    result = JrcRelationship::Priority.call(data: data.merge(health: { score: 10 }), rules: configured, kind: 'health', manual_priority: 88)
    expect(result[:score]).to eq(88)
    expect(result[:factors]['urgency_floor']).to eq(90)
  end

  it 'accepts zero and fractional weights but rejects negative, nonnumeric and nonfinite values' do
    expect(described_class.validation_errors(rules.merge('priority_trend' => 0.25))).to eq([])
    [-1, '2', false, Float::INFINITY, Float::NAN].each do |invalid|
      expect(described_class.validation_errors(rules.merge('priority_sla' => invalid))).not_to be_empty
    end
  end
end
