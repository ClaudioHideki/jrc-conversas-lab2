require 'rails_helper'

RSpec.describe JrcRelationship::ProductHealthHysteresis do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: user) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: user) }
  let(:context) { JrcRelationship::Context.new(member) }
  let(:product) { create(:jrc_crm_product, account: account) }
  let(:configuration) do
    JrcRelationship::Configuration.create!(account: account, scope_key: "product:#{product.id}", rules: { health_hysteresis_points: 5 })
  end
  let(:health) { { score: 41, band: 'risk', factors: [], config_scope_key: configuration.scope_key, config_version: configuration.version } }
  let(:attributes) do
    { account: account, assignment: assignment, viewer: user, config_scope_key: 'account', config_version: 7,
      access_signature: context.access_signature, score: 90, band: 'healthy', factors: [], calculated_at: 1.minute.ago,
      fingerprint: SecureRandom.hex(16), signals: { '_source_ids' => {}, 'product_health' => {
        product.id.to_s => health.merge(score: 39, band: 'critical')
      } } }
  end
  let(:service) { described_class.new(context: context, assignment: assignment, product_id: product.id, configuration: configuration) }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'uses the exact product model and preserved product score rather than the customer band/version' do
    previous = JrcRelationship::HealthSnapshot.create!(**attributes)
    before = previous.attributes.deep_dup
    result, sources = service.call(health)
    expect(result).to include(score: 41, raw_band: 'risk', band: 'critical', config_scope_key: configuration.scope_key)
    expect(result[:hysteresis]).to include(points: 5, previous_snapshot_id: previous.id, previous_band: 'critical', retained: true)
    expect(sources).to eq({})
    expect(previous.reload.attributes).to eq(before)
  end

  it 'preserves zero-margin/default behavior, missing observations and absence of product history' do
    expect(service.call(health)).to eq([health, {}])
    JrcRelationship::HealthSnapshot.create!(**attributes)
    expect(service.call(health.merge(score: nil, band: 'unavailable'))).to eq([health.merge(score: nil, band: 'unavailable'), {}])
    configuration.update!(rules: { health_hysteresis_points: 0 }, version: 2)
    raw = health.merge(config_version: 2)
    expect(service.call(raw)).to eq([raw, {}])
  end

  it 'requires configured recovery margins and never delays product deterioration' do
    JrcRelationship::HealthSnapshot.create!(**attributes)
    recovered, = service.call(health.merge(score: 65, band: 'attention'))
    deteriorated, = service.call(health.merge(score: 20, band: 'critical'))
    expect(recovered).to include(score: 65, band: 'attention', raw_band: 'attention')
    expect(deteriorated).to include(score: 20, band: 'critical')
    expect(deteriorated[:hysteresis][:retained]).to be(false)
  end

  it 'does not borrow another product, actor, portfolio, access signature or configuration version' do
    other = create(:user, account: account)
    other_assignment = JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: user)
    wrong_product = { '_source_ids' => {}, 'product_health' => { '9999999' => health.merge(score: 39, band: 'critical') } }
    wrong_version = { '_source_ids' => {}, 'product_health' => { product.id.to_s => health.merge(score: 39, band: 'critical', config_version: 99) } }
    wrong_scope = { '_source_ids' => {},
                    'product_health' => { product.id.to_s => health.merge(score: 39, band: 'critical', config_scope_key: 'account') } }
    [{ viewer: other }, { assignment: other_assignment }, { access_signature: 'stale-access' },
     { signals: wrong_product }, { signals: wrong_version }, { signals: wrong_scope }].each do |changes|
      JrcRelationship::HealthSnapshot.create!(**attributes, **changes, fingerprint: SecureRandom.hex(16))
    end
    expect(service.call(health)).to eq([health, {}])
  end

  it 'does not use the customer score when the latest product observation has no score' do
    missing = { '_source_ids' => {}, 'product_health' => { product.id.to_s => health.merge(score: nil, band: 'unavailable') } }
    JrcRelationship::HealthSnapshot.create!(**attributes, score: 39, band: 'critical', signals: missing)
    expect(service.call(health)).to eq([health, {}])
  end

  it 'rejects history whose referenced native source is foreign or has become private' do
    foreign = create(:account)
    owner = create(:user, account: foreign)
    order = foreign.jrc_crm_sales_orders.create!(owner: owner, status: 'approved')
    contract = foreign.jrc_crm_contracts.create!(sales_order: order, owner: owner)
    JrcRelationship::HealthSnapshot.create!(**attributes, signals: attributes[:signals].merge('_source_ids' => { 'contracts' => [contract.id] }))
    expect(service.call(health)).to eq([health, {}])
  end

  it 'cannot retain product history after native portfolio ownership is revoked' do
    JrcRelationship::HealthSnapshot.create!(**attributes)
    assignment.update!(owner: create(:user, account: account))
    expect(service.call(health)).to eq([health, {}])
  end

  it 'rejects a configuration belonging to another account' do
    foreign = JrcRelationship::Configuration.create!(account: create(:account))
    expect { described_class.new(context: context, assignment: assignment, product_id: product.id, configuration: foreign) }
      .to raise_error(ArgumentError, 'Wrong product configuration account')
  end

  context 'with the real native processor' do
    let(:weights) { JrcRelationship::Configuration::DEFAULT_WEIGHTS.transform_values { 0 }.merge('adoption' => 100) }
    let(:configuration) do
      JrcRelationship::Configuration.create!(account: account, scope_key: "product:#{product.id}", weights: weights,
                                             rules: { health_hysteresis_points: 5 })
    end
    let(:order) { account.jrc_crm_sales_orders.create!(owner: user, contact: assignment.contact, status: 'completed') }
    let(:contract) do
      record = account.jrc_crm_contracts.create!(sales_order: order, owner: user, contact: assignment.contact, ends_on: 60.days.from_now.to_date)
      record.signed_document.attach(io: StringIO.new("%PDF-1.4\nSynthetic legacy signature fixture\n%%EOF"),
                                    filename: 'synthetic-legacy-contract.pdf', content_type: 'application/pdf')
      record.update!(status: 'active', signature_status: 'signed', signature_mode: 'manual', signed_at: Time.current,
                     signed_by_name: 'Synthetic signer')
      record
    end
    let(:plan) do
      JrcRelationship::SuccessPlan.create!(account: account, assignment: assignment, owner: user, title: 'Synthetic adoption observation',
                                           goals: [{ metric: 'adoption', product_id: product.id, target: 100, current: 39,
                                                     evidence: 'Synthetic measured product usage' }])
    end

    it 'persists actual measured product stability and does not create new snapshots when only lineage changes after recovery' do
      configuration
      JrcRelationship::Configuration.create!(account: account, weights: weights)
      contract.contract_items.create!(product: product, name: product.name, status: 'active', monthly_cents: 0)
      plan
      first = JrcRelationship::Processor.new(context: JrcRelationship::Context.new(member), assignment: assignment).call
      expect(first[:product_health].fetch(product.id)).to include(score: 39, band: 'critical')
      previous = JrcRelationship::HealthSnapshot.where(assignment: assignment).last!
      preserved = previous.attributes.deep_dup
      plan.update!(goals: plan.goals.map { |goal| goal.merge('current' => 41) })
      second = JrcRelationship::Processor.new(context: JrcRelationship::Context.new(member), assignment: assignment).call
      expect(second[:product_health].fetch(product.id)).to include(score: 41, raw_band: 'risk', band: 'critical')
      plan.update!(goals: plan.goals.map { |goal| goal.merge('current' => 65) })
      recovered = JrcRelationship::Processor.new(context: JrcRelationship::Context.new(member), assignment: assignment).call
      expect(recovered[:product_health].fetch(product.id)).to include(score: 65, band: 'attention')
      count = JrcRelationship::HealthSnapshot.where(assignment: assignment).count
      2.times { JrcRelationship::Processor.new(context: JrcRelationship::Context.new(member), assignment: assignment).call }
      expect(JrcRelationship::HealthSnapshot.where(assignment: assignment).count).to eq(count)
      history = JrcRelationship::ProductHealthHistory.new(JrcRelationship::Context.new(member)).call(assignment_id: assignment.id,
                                                                                                     product_id: product.id)
      observed = history[:payload].find { |row| row[:health]['score'] == 41 }.fetch(:health)
      expect(observed).to include('raw_band' => 'risk', 'band' => 'critical', 'hysteresis' => a_hash_including('retained' => true))
      expect(previous.reload.attributes).to eq(preserved)
    end
  end
end
