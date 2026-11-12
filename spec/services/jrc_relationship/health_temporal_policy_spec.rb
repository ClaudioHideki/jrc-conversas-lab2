require 'rails_helper'

RSpec.describe JrcRelationship::HealthTemporalPolicy do
  it 'preserves the zero cooldown and integer evidence/trend windows by default' do
    expect(described_class.validation_errors(JrcRelationship::Configuration::DEFAULT_RULES)).to eq([])
    expect(described_class.validation_errors(JrcRelationship::Configuration::DEFAULT_RULES.merge('automatic_action_cooldown_hours' => 0.5))).to eq([])
  end

  it 'rejects negative, nonfinite, unbounded and untyped hours without relaxing the whole-day windows' do
    [-1, 8761, Float::INFINITY, '72', nil].each do |value|
      rules = JrcRelationship::Configuration::DEFAULT_RULES.merge('automatic_action_cooldown_hours' => value)
      expect(described_class.validation_errors(rules)).not_to be_empty
    end
    errors = described_class.validation_errors(JrcRelationship::Configuration::DEFAULT_RULES.merge('satisfaction_window_days' => 0.5,
                                                                                                   'health_trend_window_days' => 3651))
    expect(errors.length).to eq(2)
  end
end
