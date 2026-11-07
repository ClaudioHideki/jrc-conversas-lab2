require 'rails_helper'

RSpec.describe JrcRelationship::ReviewedPortfolioBatch do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:context) { JrcRelationship::Context.new(member) }
  let(:service) { described_class.new(context) }
  let(:group) { JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: 'Synthetic projected portfolio') }
  let(:records) do
    Array.new(3) do
      JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account), settings: {
                                            'capacity_workload' => { 'hours' => 2, 'points' => {
                                              'base' => 2, 'complexity_factor' => 1, 'risk_factor' => 1, 'journey_factor' => 1, 'activity_effort' => 1
                                            } }
                                          })
    end
  end
  let(:configuration) do
    JrcRelationship::Configuration.create!(account: account, scope_key: "portfolio:#{group.id}", rules: {
                                             'portfolio_capacity_limits' => [{ 'user_id' => actor.id, 'unit' => 'customers', 'maximum' => 5,
                                                                               'availability' => 1, 'dedication' => 1 }]
                                           })
  end
  let(:input) do
    { 'operation' => 'portfolio_membership', 'ids' => records.map(&:id), 'portfolio_group_id' => group.id,
      'expected_version' => group.lock_version, 'active' => true, 'justification' => 'Review the entire selected membership load',
      'request_id' => SecureRandom.uuid }
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'projects the entire final selection without duplicating existing links or global customer workload' do
    group.customer_links.create!(account: account, assignment: records.first)
    other = JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: 'Other active synthetic portfolio')
    records.each { |record| other.customer_links.create!(account: account, assignment: record) }
    configuration
    original = records.map(&:attributes)
    review = service.preview(input)
    projection = review.fetch('membership_capacity')
    expect(projection).to include('state' => 'projected', 'read_only' => true)
    expect(projection.fetch('rows').sole).to include('user_id' => actor.id, 'current' => 1, 'incoming' => 2, 'projected' => 3,
                                                     'effective_capacity' => 5, 'available_after' => 2, 'blocker' => nil)
    expect(projection).not_to have_key('source_assignment_ids')
    expect(group.customer_links.count).to eq(1)
    service.approve(review.fetch('id'), digest: review.fetch('digest'))
    service.advance(review.fetch('id'), limit: 1)
    expect(service.get(review.fetch('id')).fetch('membership_capacity')).to eq(projection)
    expect(records.map { |record| record.reload.attributes }).to eq(original)
    expect(JrcRelationship::Assignment.where(account: account).count).to eq(3)
  end

  it 'uses explicit point factors and configured availability/dedication for the selected final workload' do
    group.customer_links.create!(account: account, assignment: records.first)
    config = configuration
    entry = config.rules.fetch('portfolio_capacity_limits').sole.merge('unit' => 'points', 'maximum' => 20, 'availability' => 0.5,
                                                                       'dedication' => 0.5)
    config.update!(rules: { 'portfolio_capacity_limits' => [entry] })
    row = service.preview(input).fetch('membership_capacity').fetch('rows').sole
    expect(row).to include('unit' => 'points', 'current' => 3, 'incoming' => 6, 'projected' => 9,
                           'effective_capacity' => 5, 'available_after' => -4, 'blocker' => 'capacity_exceeded')
    expect(group.customer_links.count).to eq(1)
    expect(records.map(&:owner_id)).to eq([actor.id] * 3)
  end

  it 'does not invent equivalent hours or present missing explicit inputs as zero capacity usage' do
    config = configuration
    config.update!(rules: { 'portfolio_capacity_limits' => [config.rules.fetch('portfolio_capacity_limits').sole.merge('unit' => 'hours')] })
    records.first.update!(settings: {})
    row = service.preview(input).fetch('membership_capacity').fetch('rows').sole
    expect(row).to include('unit' => 'hours', 'blocker' => 'capacity_workload_missing')
    expect(row.keys & %w[current incoming projected effective_capacity available_after]).to eq([])
    expect(group.customer_links).not_to exist
  end

  it 'projects supplied equivalent hours without a financial or calendar conversion' do
    config = configuration
    entry = config.rules.fetch('portfolio_capacity_limits').sole.merge('unit' => 'hours', 'maximum' => 12)
    config.update!(rules: { 'portfolio_capacity_limits' => [entry] })
    row = service.preview(input).fetch('membership_capacity').fetch('rows').sole
    expect(row).to include('unit' => 'hours', 'current' => 0, 'incoming' => 6, 'projected' => 6,
                           'effective_capacity' => 12, 'available_after' => 6, 'blocker' => nil)
    expect(group.customer_links).not_to exist
  end

  it 'keeps an unlisted analyst quota unavailable rather than synthesizing a zero or an unlimited entry' do
    other = create(:user, account: account, role: :agent)
    config = configuration
    entry = config.rules.fetch('portfolio_capacity_limits').sole.merge('user_id' => other.id)
    config.update!(rules: { 'portfolio_capacity_limits' => [entry] })
    row = service.preview(input).fetch('membership_capacity').fetch('rows').sole
    expect(row).to include('user_id' => actor.id, 'blocker' => 'capacity_missing')
    expect(row.keys & %w[current incoming projected effective_capacity available_after]).to eq([])
  end

  it 'requires controlled review when the bounded full-workload read would exceed its budget' do
    configuration
    stub_const('JrcRelationship::PortfolioMembershipCapacity::MAX_ASSIGNMENTS', 2)
    projection = service.preview(input).fetch('membership_capacity')
    expect(projection).to include('state' => 'controlled_review_required', 'rows' => [])
    expect(group.customer_links).not_to exist
  end

  it 'redacts frozen workload when the current group source scope is no longer complete' do
    other = create(:user, account: account, role: :agent)
    hidden = JrcRelationship::Assignment.create!(account: account, owner: other, contact: create(:contact, account: account))
    group.customer_links.create!(account: account, assignment: hidden)
    configuration
    review = service.preview(input)
    stored = JrcRelationship::BatchReview.find(review.fetch('id')).attributes
    role = account.custom_roles.create!(name: 'Synthetic limited team manager',
                                        permissions: %w[contact_manage jrc_relationship_view jrc_relationship_manage jrc_relationship_team])
    member.update!(role: :agent, custom_role: role)
    projection = service.get(review.fetch('id')).fetch('membership_capacity')
    expect(projection).to include('state' => 'scope_denied', 'rows' => [])
    expect(projection).not_to have_key('source_assignment_ids')
    expect(JrcRelationship::BatchReview.find(review.fetch('id')).attributes).to eq(stored)
    expect(service.preview(input.merge('request_id' => SecureRandom.uuid)).fetch('membership_capacity')).to include('state' => 'scope_denied',
                                                                                                                    'rows' => [])
  end

  it 'treats unconfigured group quotas separately from a numeric zero limit' do
    result = service.preview(input).fetch('membership_capacity')
    expect(result).to include('state' => 'not_configured', 'read_only' => true, 'rows' => [])
    expect(group.customer_links).not_to exist
  end

  it 'does not reveal an old load source after it leaves the group and becomes invisible to the current viewer' do
    group.customer_links.create!(account: account, assignment: records.first)
    configuration
    review = service.preview(input.merge('ids' => records.drop(1).map(&:id)))
    configuration.update!(rules: {})
    JrcRelationship::PortfolioGroups.new(context).set_customers!(
      group.id, ids: [records.first.id], active: false, expected_version: group.lock_version,
                reason: 'Synthetic source link removed'
    )
    other = create(:user, account: account, role: :agent)
    records.first.update!(owner: other)
    role = account.custom_roles.create!(name: 'Synthetic historical-source restriction',
                                        permissions: %w[contact_manage jrc_relationship_view jrc_relationship_manage jrc_relationship_team])
    member.update!(role: :agent, custom_role: role)
    projection = service.get(review.fetch('id')).fetch('membership_capacity')
    expect(group.customer_links.where(active: true)).not_to exist
    expect(projection).to include('state' => 'scope_denied', 'rows' => [])
  end

  it 'uses the native current owner eligibility check without treating a configured quota as an access grant' do
    other = create(:user, account: account, role: :agent)
    records.each { |record| record.update!(owner: other) }
    entry = { 'user_id' => other.id, 'unit' => 'customers', 'maximum' => 5, 'availability' => 1, 'dedication' => 1 }
    JrcRelationship::Configuration.create!(account: account, scope_key: "portfolio:#{group.id}", rules: { 'portfolio_capacity_limits' => [entry] })
    role = account.custom_roles.create!(name: 'Synthetic revoked source-module access', permissions: [])
    account.account_users.find_by!(user: other).update!(role: :agent, custom_role: role)
    row = service.preview(input).fetch('membership_capacity').fetch('rows').sole
    expect(row).to include('user_id' => other.id, 'blocker' => 'capacity_owner_unavailable', 'projected' => 3)
    expect(group.customer_links).not_to exist
  end

  it 'reads a legacy immutable review without synthesizing a captured projection or changing its stored snapshot' do
    preview = service.preview(input)
    saved = JrcRelationship::BatchReview.find(preview.fetch('id'))
    inputs = saved.inputs.merge('request_id' => SecureRandom.uuid)
    snapshot = saved.snapshot.except('membership_capacity')
    legacy = JrcRelationship::BatchReview.create!(account: account, actor: actor, inputs: inputs, snapshot: snapshot,
                                                  request_id: inputs.fetch('request_id'), expires_at: saved.expires_at,
                                                  digest: JrcRelationship::BatchReviewPlan.new(context).digest([inputs, snapshot]))
    records.each_with_index { |record, ordinal| legacy.items.create!(account: account, assignment: record, ordinal: ordinal) }
    before = legacy.attributes
    expect(service.get(legacy.id)).not_to have_key('membership_capacity')
    expect(legacy.reload.attributes).to eq(before)
  end
end
