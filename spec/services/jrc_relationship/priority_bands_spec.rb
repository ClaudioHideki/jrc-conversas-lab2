require 'rails_helper'

RSpec.describe JrcRelationship::PriorityBands do
  let(:bands) { %w[P0 P1 P2 P3].zip([90, 80, 60, 0]).map { |code, minimum| { 'code' => code, 'minimum' => minimum } } }
  let(:rules) { JrcRelationship::Configuration::DEFAULT_RULES }
  let(:data) { { health: { score: 100 }, mrr_cents: 0, renewal_on: Date.current + 120, days_without_contact: 0 } }

  it 'preserves the exact legacy result and requires explicit configured limits' do
    legacy = JrcRelationship::Priority.call(data: data, rules: rules, kind: 'health')
    expect(legacy[:factors].keys.grep(/priority_band/)).to eq([])
    expect(JrcRelationship::Priority.call(data: data, rules: rules.merge('priority_bands' => []), kind: 'health')).to eq(legacy)
    expect(rules).not_to have_key('priority_bands')
  end

  it 'classifies every boundary without changing the manual score or urgency evidence' do
    { 100 => 'P0', 90 => 'P0', 89 => 'P1', 80 => 'P1', 79 => 'P2', 60 => 'P2', 59 => 'P3', 0 => 'P3' }.each do |score, code|
      result = JrcRelationship::Priority.call(data: data.merge(health: { score: 10 }), rules: rules.merge('priority_bands' => bands),
                                              kind: 'health', manual_priority: score)
      expect(result[:score]).to eq(score)
      expect(result[:factors]).to include('priority_band' => code, 'priority_band_score' => score, 'urgency_floor' => 90)
      expect(JSON.parse(result[:factors].fetch('priority_band_policy'))).to eq(bands)
    end
  end

  it 'rejects malformed, reordered, overlapping, incomplete or noninteger limits rather than fabricating production cuts' do
    [nil, {}, [bands.first], bands.reverse, bands.map { |row| row.merge('minimum' => 10) },
     bands.map { |row| row.merge('minimum' => row['minimum'].to_s) }, bands.map { |row| row.merge('unknown' => 1) },
     bands.map { |row| row['code'] == 'P3' ? row.merge('minimum' => 1) : row }].each do |invalid|
      expect { described_class.validate!(invalid) }.to raise_error(ArgumentError)
    end
    expect { described_class.validate!([]) }.not_to raise_error
  end

  it 'uses the captured policy for a later system priority change and removes labels only on explicit recalculation without bands' do
    factors = described_class.capture({ 'urgency_floor' => 0 }, 65, bands)
    refreshed = described_class.refresh_captured(factors, 100)
    expect(refreshed).to include('priority_band' => 'P0', 'priority_band_score' => 100, 'priority_band_policy' => bands.to_json)
    expect(factors['priority_band']).to eq('P2')
    expect(described_class.capture(refreshed, 100, [])).to eq('urgency_floor' => 0)
  end
end
