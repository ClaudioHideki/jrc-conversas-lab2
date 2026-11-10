require 'rails_helper'

RSpec.describe JrcRelationship::HealthScore do
  it 'keeps measured coverage separate from the configured neutral imputation weight' do
    result = described_class.call(observations: { contact: { normalized: 90 }, finance: { normalized: nil } },
                                   weights: { contact: 40, finance: 60 }, rules: { 'missing_factor_policy' => 'neutral' })
    expect(result).to include(coverage_weight: 40, calculation_weight: 100, score: 66)
    expect(result[:factors].last).to include(available: false, imputed: true)
  end

  it 'does not turn missing data into a healthy customer under any missing-data policy' do
    %w[neutral renormalize block].each do |policy|
      result = described_class.call(observations: { contact: { normalized: nil } }, weights: { contact: 100 },
                                     rules: { 'missing_factor_policy' => policy })
      expect(result[:coverage_weight]).to eq(0)
      expect(result[:band]).to eq('unavailable')
      expect(result[:score]).to be_nil
      expect(result[:factors].first[:available]).to be(false)
    end
  end
end
