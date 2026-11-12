require 'rails_helper'

RSpec.describe JrcRelationship::SatisfactionEvidence do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: user) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: user, contact: create(:contact, account: account)) }
  let(:context) { JrcRelationship::Context.new(member) }
  let(:customer) { assignment.customer_context(member) }
  let(:rules) { JrcRelationship::Configuration::DEFAULT_RULES }
  let(:old_answer) do
    JrcRelationship::Survey.create!(account: account, assignment: assignment, owner: user, kind: 'nps', token_digest: SecureRandom.hex,
                                    expires_at: 1.day.from_now, status: 'responded', score: 2, responded_at: 40.days.ago)
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'retains the default90-day source window and the actual answer timestamp' do
    old_answer
    result = JrcRelationship::SatisfactionSignals.new(context, assignment, customer, rules).call
    expect(result).to include(nps_score: 2.0, window_days: 90)
    expect(result[:evidence]).to include(state: 'current', observed_at: old_answer.responded_at.iso8601(6), source: 'nps')
    expect(result[:source_ids]['surveys']).to include(old_answer.id)
  end

  it 'marks old authorized evidence stale without imputing a zero or changing the immutable response' do
    original = old_answer.attributes.deep_dup
    result = JrcRelationship::SatisfactionSignals.new(context, assignment, customer, rules.merge('satisfaction_window_days' => 14)).call
    expect(result[:nps_score]).to be_nil
    expect(result[:evidence]).to include(state: 'stale', window_days: 14, observed_at: old_answer.responded_at.iso8601(6))
    expect(result[:source_ids]['surveys']).to eq([old_answer.id])
    expect(old_answer.reload.attributes).to eq(original)
  end

  it 'keeps absent, future and foreign answers out of the observed score' do
    foreign = create(:account)
    foreign_user = create(:user, account: foreign)
    foreign_assignment = JrcRelationship::Assignment.create!(account: foreign, owner: foreign_user, contact: create(:contact, account: foreign))
    JrcRelationship::Survey.create!(account: foreign, assignment: foreign_assignment, kind: 'nps', token_digest: SecureRandom.hex,
                                    expires_at: 1.day.from_now, status: 'responded', score: 10, responded_at: Time.current)
    JrcRelationship::Survey.create!(account: account, assignment: assignment, kind: 'nps', token_digest: SecureRandom.hex,
                                    expires_at: 2.days.from_now, status: 'responded', score: 10, responded_at: 1.day.from_now)
    result = JrcRelationship::SatisfactionSignals.new(context, assignment, customer, rules).call
    expect(result[:nps_score]).to be_nil
    expect(result[:evidence]).to eq(state: 'missing', window_days: 90)
    expect(result[:source_ids]['surveys']).to be_empty
  end

  it 'binds stale native CSAT evidence to its native row and denies the cached evidence after inbox access is lost' do
    inbox = create(:inbox, account: account)
    other = create(:user, account: account)
    conversation = create(:conversation, account: account, inbox: inbox, contact: assignment.contact, assignee: other)
    message = create(:message, account: account, conversation: conversation, content_type: :input_csat)
    response = CsatSurveyResponse.create!(account: account, conversation: conversation, contact: assignment.contact,
                                          message: message, rating: 3, created_at: 20.days.ago)
    result = JrcRelationship::SatisfactionSignals.new(context, assignment, customer, rules.merge('satisfaction_window_days' => 7)).call
    expect(result[:csat_score]).to be_nil
    expect(result[:evidence]).to include(state: 'stale', source: 'csat')
    expect(result[:source_ids]['csat']).to eq([response.id])
    snapshot = JrcRelationship::HealthSnapshot.create!(account: account, assignment: assignment, viewer: user,
                                                       config_scope_key: 'account', config_version: 1, score: 50, band: 'risk',
                                                       fingerprint: SecureRandom.hex, calculated_at: Time.current,
                                                       access_signature: context.access_signature, signals: { '_source_ids' => result[:source_ids] })
    member.update!(role: :agent)
    fresh = JrcRelationship::Context.new(member)
    expect(JrcRelationship::SnapshotAccess.scope(fresh, JrcRelationship::HealthSnapshot.where(id: snapshot.id))).to be_empty
  end

  it 'persists bounded whole-day windows in versioned configuration and rejects fractional or unbounded windows' do
    configuration = JrcRelationship::Configuration.create!(account: account, rules: { satisfaction_window_days: 14, health_trend_window_days: 7 })
    expect(configuration.effective_rules).to include('satisfaction_window_days' => 14, 'health_trend_window_days' => 7)
    configuration.rules = { satisfaction_window_days: 0.5, health_trend_window_days: 3651 }
    expect(configuration).not_to be_valid
  end

  it 'uses the exact product evidence window without changing the customer window or concealing source lineage' do
    old_answer
    weights = JrcRelationship::Configuration::DEFAULT_WEIGHTS.transform_values { 0 }.merge('satisfaction' => 100)
    JrcRelationship::Configuration.create!(account: account, weights: weights)
    product = create(:jrc_crm_product, account: account)
    config = JrcRelationship::Configuration.create!(account: account, scope_key: "product:#{product.id}", weights: weights,
                                                    rules: { satisfaction_window_days: 14 })
    order = account.jrc_crm_sales_orders.create!(owner: user, contact: assignment.contact, status: 'completed')
    contract = account.jrc_crm_contracts.create!(sales_order: order, owner: user, contact: assignment.contact, ends_on: 60.days.from_now.to_date)
    contract.signed_document.attach(io: StringIO.new("%PDF-1.4\nSynthetic local legacy signature fixture\n%%EOF"),
                                    filename: 'synthetic-window-contract.pdf', content_type: 'application/pdf')
    contract.update!(status: 'active', signature_status: 'signed', signature_mode: 'manual', signed_at: Time.current,
                     signed_by_name: 'Synthetic signer')
    contract.contract_items.create!(product: product, name: product.name, status: 'active', monthly_cents: 0)
    data = JrcRelationship::CustomerSignals.new(assignment: assignment, context: context).call
    expect(data.dig(:health, :score)).to eq(20)
    expect(data[:product_health].fetch(product.id)).to include(score: nil, band: 'unavailable', config_version: config.version)
    expect(data[:product_health].fetch(product.id).fetch(:factors).find { |row| row[:factor] == 'satisfaction' }[:measurement])
      .to include(state: 'stale', window_days: 14)
    expect(data[:_source_ids][:surveys]).to include(old_answer.id)
  end
end
