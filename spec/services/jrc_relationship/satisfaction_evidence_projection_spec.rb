require 'rails_helper'

RSpec.describe JrcRelationship::SatisfactionEvidenceProjection do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: user)) }
  let(:configuration) { JrcRelationship::Configuration.create!(account: account, rules: { satisfaction_window_days: 14 }) }
  let(:signals) do
    { health: { score: 20, band: 'critical', factors: [{ factor: 'satisfaction', measurement: {
      state: 'current', window_days: 14, observed_at: 10.days.ago.iso8601(6), source: 'nps'
    } }] }, _source_ids: {} }
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'marks an old cached observation stale at read time while retaining its historical score and timestamp' do
    frozen = signals.deep_dup
    value = described_class.call(signals: signals, configuration: configuration, now: 5.days.from_now)
    expect(value).to include(state: 'stale', captured_state: 'current', recalculation_required: true)
    expect(signals).to eq(frozen)
    expect(value[:observed_at]).to eq(frozen.dig(:health, :factors, 0, :measurement, :observed_at))
  end

  it 'requires recalculation after a window change rather than claiming the old score used the new policy' do
    configuration.update!(rules: { satisfaction_window_days: 7 }, version: 2)
    expect(described_class.call(signals: signals, configuration: configuration))
      .to include(state: 'requires_refresh', window_days: 14, current_window_days: 7, recalculation_required: true)
  end

  it 'presents cached freshness through the native authorized portfolio projection without rewriting the snapshot' do
    assignment = JrcRelationship::Assignment.create!(account: account, owner: user, contact: create(:contact, account: account))
    snapshot = JrcRelationship::HealthSnapshot.create!(account: account, assignment: assignment, viewer: user,
                                                       config_scope_key: configuration.scope_key, config_version: configuration.version,
                                                       score: 20, band: 'critical', fingerprint: SecureRandom.hex, calculated_at: 10.days.ago,
                                                       access_signature: context.access_signature, signals: signals)
    original = snapshot.attributes.deep_dup
    travel_to(5.days.from_now) do
      presenter = JrcRelationship::Presenter.new(context)
      presenter.preload([assignment])
      result = presenter.assignment(assignment)
      expect(result.dig(:signals, :health, :score)).to eq(20)
      expect(result.dig(:signals, :satisfaction_evidence)).to include(state: 'stale', recalculation_required: true)
      expect(result[:calculated_at]).to eq(snapshot.calculated_at)
    end
    expect(snapshot.reload.attributes).to eq(original)
  end

  it 'uses the same read-time freshness through the native NICO tool without allowing foreign portfolio access' do
    account.update!(custom_attributes: { 'nico_enabled' => true })
    assignment = JrcRelationship::Assignment.create!(account: account, owner: user, contact: create(:contact, account: account))
    snapshot = JrcRelationship::HealthSnapshot.create!(account: account, assignment: assignment, viewer: user,
                                                       config_scope_key: configuration.scope_key, config_version: configuration.version,
                                                       score: 20, band: 'critical', fingerprint: SecureRandom.hex, calculated_at: 10.days.ago,
                                                       access_signature: context.access_signature, signals: signals)
    access = JrcNico::OperationalAccess.new(account: account, user: user)
    travel_to(5.days.from_now) do
      result = JrcNico::ToolExecutor.new(access).call('read_relationship_customer', { 'assignment_id' => assignment.id })
      expect(result.dig(:health, :evidence_freshness)).to include(state: 'stale', recalculation_required: true)
      expect(result.dig(:health, :score)).to eq(20)
      expect(result[:calculated_at]).to eq(snapshot.calculated_at)
    end
    foreign = create(:account)
    record = JrcRelationship::Assignment.create!(account: foreign, contact: create(:contact, account: foreign))
    expect do
      JrcNico::ToolExecutor.new(access).call('read_relationship_customer', { 'assignment_id' => record.id })
    end.to raise_error(ActiveRecord::RecordNotFound)
  end
end
