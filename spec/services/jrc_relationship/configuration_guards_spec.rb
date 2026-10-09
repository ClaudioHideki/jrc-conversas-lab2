require 'rails_helper'

RSpec.describe JrcRelationship::Configuration do
  include_context 'JRC Service Desk domain'
  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master', 'jrc_relationship')
  end

  it 'requires finite nonnegative weights whose total is exactly 100' do
    valid = described_class.new(account: sd_account)
    expect(valid).to be_valid
    valid.weights = described_class::DEFAULT_WEIGHTS.merge('finance' => 11)
    expect(valid).not_to be_valid
    valid.weights = described_class::DEFAULT_WEIGHTS.merge('finance' => -1)
    expect(valid).not_to be_valid
  end

  it 'supports explicit renormalize, neutral and block policies without hiding missing evidence' do
    observations = { 'known' => { raw: 80, normalized: 80, evidence: 'Observed' },
                     'missing' => { raw: nil, normalized: nil, evidence: 'Unavailable' } }
    weights = { 'known' => 50, 'missing' => 50 }
    renormalized = JrcRelationship::HealthScore.call(observations: observations, weights: weights)
    neutral = JrcRelationship::HealthScore.call(observations: observations, weights: weights, rules: { 'missing_factor_policy' => 'neutral' })
    blocked = JrcRelationship::HealthScore.call(observations: observations, weights: weights, rules: { 'missing_factor_policy' => 'block' })
    expect(renormalized[:score]).to eq(80)
    expect(neutral[:score]).to eq(65)
    expect(neutral[:factors].last).to include(available: false, imputed: true)
    expect(blocked).to include(score: nil, band: 'unavailable', blocked: true)
  end

  it 'rejects invalid missing-factor policy and scope target in another account' do
    record = described_class.new(account: sd_account, rules: { missing_factor_policy: 'invent' })
    expect(record).not_to be_valid
    company = sd_foreign_account.master_companies.create!(name: 'Other tenant')
    record.scope_key = "company:#{company.id}"
    expect(record).not_to be_valid
    expect(record.errors[:scope_key]).to be_present
  end

  it 'restricts configuration grants to assigned companies and native authorized units' do
    sd_account.enable_features!('jrc_crm')
    sd_account_user.update!(role: :agent, custom_role: create(:custom_role, account: sd_account,
                                                                            permissions: %w[contact_manage jrc_relationship_view
                                                                                            jrc_relationship_manage jrc_relationship_configure]))
    own = sd_account.master_companies.create!(name: 'Assigned company')
    other = sd_account.master_companies.create!(name: 'Other company')
    unit = JrcCrm::BusinessUnit.create!(account: sd_account, name: 'Assigned unit', code: 'OWN')
    other_unit = JrcCrm::BusinessUnit.create!(account: sd_account, name: 'Other unit', code: 'OTHER')
    JrcRelationship::Assignment.create!(account: sd_account, company: own, business_unit: unit, owner: sd_user)
    context = JrcRelationship::Context.new(sd_account_user)
    expect { context.authorize_configuration_scope!("company:#{own.id}") }.not_to raise_error
    expect { context.authorize_configuration_scope!("unit:#{unit.id}") }.not_to raise_error
    expect { context.authorize_configuration_scope!("company:#{other.id}") }.to raise_error(ActiveRecord::RecordNotFound)
    expect { context.authorize_configuration_scope!("unit:#{other_unit.id}") }.to raise_error(ActiveRecord::RecordNotFound)
    expect { context.authorize_configuration_scope!('account') }.to raise_error(Pundit::NotAuthorizedError)
  end
end
