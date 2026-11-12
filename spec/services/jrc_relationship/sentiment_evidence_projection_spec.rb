require 'rails_helper'

RSpec.describe JrcRelationship::SentimentEvidenceProjection do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: actor)) }
  let(:configuration) { JrcRelationship::Configuration.create!(account: account, rules: { sentiment_window_days: 14 }) }
  let(:signals) do
    { health: { score: 20, band: 'critical', factors: [{ factor: 'sentiment', measurement: {
      state: 'current', window_days: 14, observed_at: 10.days.ago.iso8601(6), source: 'existing_public_message_sentiment'
    } }] }, _source_ids: {} }
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'marks an actual old observation stale at read time without rewriting the captured score or evidence' do
    frozen = signals.deep_dup
    travel_to(5.days.from_now) do
      result = described_class.annotate(signals: signals, configuration: configuration)
      expect(result[:sentiment_evidence]).to include(state: 'stale', captured_state: 'current', recalculation_required: true)
      expect(result[:health]).to include(score: 20, band: 'critical')
      expect(result.dig(:health, :sentiment_evidence_freshness)).to eq(result[:sentiment_evidence])
    end
    expect(signals).to eq(frozen)
  end

  it 'requires recalculation after a native window change instead of claiming the historical score used it' do
    configuration.update!(rules: { sentiment_window_days: 7 }, version: 2)
    result = described_class.annotate(signals: signals, configuration: configuration)
    expect(result[:sentiment_evidence]).to include(state: 'requires_refresh', current_window_days: 7, window_days: 14,
                                                   recalculation_required: true)
  end

  it 'preserves legacy scores without inventing a measurement date for snapshots without sentiment evidence' do
    original = { health: { score: 60, factors: [{ factor: 'sentiment', normalized: 60 }] } }
    expect(described_class.annotate(signals: original, configuration: configuration)).to equal(original)
  end

  it 'rejects future or malformed captured dates without altering the historical score' do
    ['invalid-date', 1.day.from_now.iso8601(6)].each do |date|
      original = signals.deep_dup
      original[:health][:factors].first[:measurement][:observed_at] = date
      result = described_class.annotate(signals: original, configuration: configuration)
      expect(result[:sentiment_evidence]).to include(state: 'unavailable', recalculation_required: true)
      expect(result[:health][:score]).to eq(20)
    end
  end

  it 'returns the same truthful freshness from native portfolio and NICO reads while denying a foreign assignment' do
    account.update!(custom_attributes: { 'nico_enabled' => true })
    assignment = JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account))
    snapshot = JrcRelationship::HealthSnapshot.create!(account: account, assignment: assignment, viewer: actor,
                                                       config_scope_key: configuration.scope_key, config_version: configuration.version,
                                                       score: 20, band: 'critical', fingerprint: SecureRandom.hex, calculated_at: 10.days.ago,
                                                       access_signature: context.access_signature, signals: signals)
    original = snapshot.attributes.deep_dup
    travel_to(5.days.from_now) do
      presenter = JrcRelationship::Presenter.new(context)
      presenter.preload([assignment])
      record = presenter.assignment(assignment)
      access = JrcNico::OperationalAccess.new(account: account, user: actor)
      result = JrcNico::ToolExecutor.new(access).call('read_relationship_customer', { 'assignment_id' => assignment.id })
      expect([record.dig(:signals, :health, :sentiment_evidence_freshness), result.dig(:health, :sentiment_evidence_freshness)])
        .to all(include(state: 'stale', recalculation_required: true))
      expect([record.dig(:signals, :health, :score), result.dig(:health, :score)]).to eq([20, 20])
    end
    expect(snapshot.reload.attributes).to eq(original)
    foreign = create(:account)
    other = JrcRelationship::Assignment.create!(account: foreign, contact: create(:contact, account: foreign))
    expect do
      JrcNico::ToolExecutor.new(JrcNico::OperationalAccess.new(account: account, user: actor))
                           .call('read_relationship_customer', { 'assignment_id' => other.id })
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'keeps the existing90-day default and enforces native whole-day configuration bounds' do
    expect(JrcRelationship::Configuration::DEFAULT_RULES.fetch('sentiment_window_days')).to eq(90)
    [nil, 0, -1, 1.5, 3651, '14'].each do |value|
      candidate = JrcRelationship::Configuration.new(account: account, rules: { sentiment_window_days: value })
      expect(candidate).not_to be_valid
      expect(candidate.errors[:rules].join).to include('sentiment_window_days')
    end
  end
end
