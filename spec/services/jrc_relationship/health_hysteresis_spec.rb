require 'rails_helper'

RSpec.describe JrcRelationship::HealthHysteresis do
  let(:rules) { JrcRelationship::Configuration::DEFAULT_RULES.merge('health_hysteresis_points' => 5) }

  it 'requires the configured recovery margin at every boundary and never delays deterioration' do
    expect(described_class.band(score: 40, previous_band: 'critical', rules: rules)).to eq('critical')
    expect(described_class.band(score: 44.99, previous_band: 'critical', rules: rules)).to eq('critical')
    expect(described_class.band(score: 45, previous_band: 'critical', rules: rules)).to eq('risk')
    expect(described_class.band(score: 60.1, previous_band: 'risk', rules: rules)).to eq('risk')
    expect(described_class.band(score: 65, previous_band: 'risk', rules: rules)).to eq('attention')
    expect(described_class.band(score: 80, previous_band: 'attention', rules: rules)).to eq('attention')
    expect(described_class.band(score: 85, previous_band: 'attention', rules: rules)).to eq('healthy')
  end

  it 'never delays deterioration across one or several risk bands' do
    expect(described_class.band(score: 39.99, previous_band: 'healthy', rules: rules)).to eq('critical')
    expect(described_class.band(score: 79.99, previous_band: 'healthy', rules: rules)).to eq('attention')
  end

  it 'preserves zero-margin behavior, missing evidence and recovery across several bands' do
    expect(described_class.band(score: 60, previous_band: 'critical', rules: rules.merge('health_hysteresis_points' => 0))).to eq('attention')
    expect(described_class.band(score: nil, previous_band: 'critical', rules: rules)).to eq('unavailable')
    expect(described_class.band(score: 90, previous_band: 'critical', rules: rules)).to eq('healthy')
    expect(described_class.band(score: 60, previous_band: 'unavailable', rules: rules)).to eq('attention')
  end

  context 'with persisted native customer data' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account, role: :agent) }
    let(:member) { account.account_users.find_by!(user: user) }
    let(:assignment) { JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: user) }
    let(:context) { JrcRelationship::Context.new(member) }
    let!(:configuration) { JrcRelationship::Configuration.create!(account: account, rules: { health_hysteresis_points: 5 }) }
    let(:attributes) do
      { account: account, assignment: assignment, viewer: user, config_scope_key: 'account', config_version: 1,
        access_signature: context.access_signature, score: 39, band: 'critical', factors: [],
        signals: { '_source_ids' => {} }, calculated_at: 1.minute.ago, fingerprint: SecureRandom.hex(16) }
    end
    let(:health) { { score: 41, band: 'risk', factors: [{ normalized: 41 }] } }

    before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

    it 'uses an authorized immutable snapshot and exposes the measured score and retention explanation separately' do
      previous = JrcRelationship::HealthSnapshot.create!(**attributes)
      result, sources = described_class.new(context: context, assignment: assignment).call(health)
      expect(result).to include(score: 41, raw_band: 'risk', band: 'critical', factors: health[:factors])
      expect(result[:hysteresis]).to include(points: 5, retained: true, previous_snapshot_id: previous.id)
      expect(sources).to eq({})
      expect(previous.reload).to have_attributes(score: 39, band: 'critical')
    end

    it 'does not borrow state from another viewer, model version, access signature or portfolio' do
      other_user = create(:user, account: account)
      other_assignment = JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: user)
      [{ viewer: other_user }, { config_version: 2 }, { access_signature: 'different-access' }, { assignment: other_assignment }].each do |changes|
        JrcRelationship::HealthSnapshot.create!(**attributes, **changes, fingerprint: SecureRandom.hex(16))
      end
      expect(described_class.new(context: context, assignment: assignment).call(health)).to eq([health, {}])
    end

    it 'rejects history whose evidence is no longer visible, including source IDs in another account' do
      foreign = create(:account)
      other_user = create(:user, account: foreign)
      other_order = foreign.jrc_crm_sales_orders.create!(owner: other_user, status: 'approved')
      other_contract = foreign.jrc_crm_contracts.create!(sales_order: other_order, owner: other_user)
      JrcRelationship::HealthSnapshot.create!(**attributes, signals: { '_source_ids' => { 'contracts' => [other_contract.id] } })
      expect(described_class.new(context: context, assignment: assignment).call(health)).to eq([health, {}])
    end

    it 'does not retain a historical band when native assignment ownership is revoked' do
      JrcRelationship::HealthSnapshot.create!(**attributes)
      assignment.update!(owner: create(:user, account: account))
      expect(described_class.new(context: context, assignment: assignment).call(health)).to eq([health, {}])
    end

    it 'persists stable bands through the real processor and keeps raw measurements and historical versions unchanged' do
      weights = JrcRelationship::Configuration::DEFAULT_WEIGHTS.transform_values { 0 }.merge('relationship' => 100)
      configuration.update!(weights: weights, rules: { health_hysteresis_points: 5, no_contact_days: 100 })
      assignment.update!(created_at: 61.days.ago)
      first = JrcRelationship::Processor.new(context: context, assignment: assignment).call
      expect(first.dig(:health, :score)).to eq(39)
      previous = JrcRelationship::HealthSnapshot.where(assignment: assignment).last!
      captured = previous.attributes.deep_dup
      assignment.update!(created_at: 59.days.ago)
      fresh_context = JrcRelationship::Context.new(member)
      next_data = JrcRelationship::Processor.new(context: fresh_context, assignment: assignment).call
      expect(next_data[:health]).to include(score: 41, raw_band: 'risk', band: 'critical')
      expect(JrcRelationship::HealthSnapshot.where(assignment: assignment).last!.band).to eq('critical')
      expect(assignment.actions.where(kind: 'health').count).to eq(1)
      expect(JrcRelationship::RiskCase.where(assignment: assignment, kind: 'health').first!.severity).to eq('critical')
      expect(previous.reload.attributes).to eq(captured)
      count = JrcRelationship::HealthSnapshot.where(assignment: assignment).count
      2.times { JrcRelationship::Processor.new(context: JrcRelationship::Context.new(member), assignment: assignment).call }
      expect(JrcRelationship::HealthSnapshot.where(assignment: assignment).count).to eq(count)
    end

    it 'does not duplicate a recovered customer observation when only the previous band and snapshot lineage change' do
      weights = JrcRelationship::Configuration::DEFAULT_WEIGHTS.transform_values { 0 }.merge('relationship' => 100)
      configuration.update!(weights: weights, rules: { health_hysteresis_points: 5, no_contact_days: 100 })
      assignment.update!(created_at: 61.days.ago)
      JrcRelationship::Processor.new(context: JrcRelationship::Context.new(member), assignment: assignment).call
      assignment.update!(created_at: 35.days.ago)
      recovered = JrcRelationship::Processor.new(context: JrcRelationship::Context.new(member), assignment: assignment).call
      expect(recovered[:health]).to include(score: 65, raw_band: 'attention', band: 'attention')
      count = JrcRelationship::HealthSnapshot.where(assignment: assignment).count
      2.times { JrcRelationship::Processor.new(context: JrcRelationship::Context.new(member), assignment: assignment).call }
      expect(JrcRelationship::HealthSnapshot.where(assignment: assignment).count).to eq(count)
    end
  end
end
