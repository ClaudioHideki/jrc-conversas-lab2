require 'rails_helper'

RSpec.describe JrcRelationship::Presenter do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: actor)) }
  let(:weights) { JrcRelationship::Configuration::DEFAULT_WEIGHTS.transform_values { 0 }.merge('relationship' => 100) }
  let(:rules) { { 'no_contact_days' => 100, 'risk_threshold' => 70 } }
  let(:days) { 35 }
  let(:assignment) do
    JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: actor,
                                        created_at: days.days.ago)
  end
  let(:result) { described_class.new(context).recommendations(assignment) }

  around { |example| travel_to(Time.zone.local(2026, 11, 6, 12)) { example.run } }

  before do
    account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    JrcRelationship::Configuration.create!(account: account, scope_key: 'account', weights: weights, rules: rules)
  end

  it 'uses the effective configured risk threshold for actual observed factors' do
    expect(result.fetch(:health).fetch(:score)).to eq(65)
    expect(result.fetch(:evidence)).to include(include(factor: 'relationship', normalized: 65))
  end

  context 'when a low factor has explicitly zero weight' do
    let(:weights) { super().merge('relationship' => 0, 'finance' => 100) }
    let(:days) { 65 }

    it 'does not recommend corrective work for an excluded factor' do
      expect([result.fetch(:health).fetch(:score), result.fetch(:evidence)]).to eq([100, []])
    end
  end

  context 'when the only weighted factor is unavailable' do
    let(:weights) { super().merge('relationship' => 0, 'adoption' => 100) }

    it 'does not present maintaining cadence as an evidence-based recommendation' do
      expect([result[:recommendation_state], result.fetch(:health).fetch(:score)]).to eq(['unavailable', nil])
      expect(result.fetch(:recommended_action)).not_to eq('Manter cadência de relacionamento')
    end
  end

  context 'when missing-data policy blocks the score' do
    let(:weights) { super().merge('relationship' => 0, 'adoption' => 50, 'finance' => 50) }
    let(:rules) { super().merge('missing_factor_policy' => 'block') }

    it 'keeps the blocked recommendation unavailable despite other observed healthy data' do
      expect([result[:recommendation_state], result.fetch(:health).fetch(:blocked)]).to eq(['unavailable', true])
    end
  end

  context 'when the factor is at the exact configured risk boundary' do
    let(:days) { 30 }

    it 'keeps the existing attention boundary and suggests no correction below a different hardcoded threshold' do
      expect([result.fetch(:health).fetch(:score), result.fetch(:evidence)]).to eq([70, []])
    end
  end
end
