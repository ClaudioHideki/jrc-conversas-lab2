require 'rails_helper'

RSpec.describe JrcRelationship::HealthTrend do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: user)) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: user, contact: create(:contact, account: account)) }
  let(:configuration) { JrcRelationship::Configuration.create!(account: account, rules: { health_trend_window_days: 14 }) }
  let(:attributes) do
    { account: account, assignment: assignment, viewer: user, config_scope_key: configuration.scope_key, config_version: configuration.version,
      score: 40, band: 'risk', fingerprint: SecureRandom.hex, calculated_at: 10.days.ago, access_signature: context.access_signature,
      factors: [], signals: { '_source_ids' => {} } }
  end
  let(:service) { described_class.new(context: context, assignment: assignment, configuration: configuration) }
  let(:health) { { score: 60, band: 'attention', factors: [] } }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'compares actual authorized observations within the versioned window and preserves the immutable baseline' do
    baseline = JrcRelationship::HealthSnapshot.create!(**attributes)
    original = baseline.attributes.deep_dup
    result = service.call(health)
    expect(result[:trend]).to include(state: 'improved', window_days: 14, delta: 20.0, baseline_snapshot_id: baseline.id)
    expect(result[:trend][:baseline_at]).to eq(baseline.calculated_at)
    expect(baseline.reload.attributes).to eq(original)
    expect(service.call(health.merge(score: 30))[:trend]).to include(state: 'declined', delta: -10.0)
  end

  it 'distinguishes unavailable and insufficient observations rather than inventing a zero baseline' do
    expect(service.call(health)[:trend]).to eq(state: 'insufficient', window_days: 14)
    expect(service.call(health.merge(score: nil))[:trend]).to eq(state: 'unavailable', window_days: 14)
  end

  it 'does not borrow old, future, different-viewer, different-model or different-access observations' do
    other = create(:user, account: account)
    [{ calculated_at: 15.days.ago }, { calculated_at: 1.day.from_now }, { viewer: other }, { config_version: 2 },
     { access_signature: 'old-access' }].each do |changes|
      JrcRelationship::HealthSnapshot.create!(**attributes, **changes, fingerprint: SecureRandom.hex)
    end
    expect(service.call(health)[:trend][:state]).to eq('insufficient')
  end

  it 'reauthorizes native baseline evidence instead of exposing a foreign source through a cached score' do
    foreign = create(:contact, account: create(:account))
    conversation = create(:conversation, account: foreign.account, contact: foreign)
    JrcRelationship::HealthSnapshot.create!(**attributes, signals: { '_source_ids' => { 'conversations' => [conversation.id] } })
    expect(service.call(health)[:trend][:state]).to eq('insufficient')
  end
end
