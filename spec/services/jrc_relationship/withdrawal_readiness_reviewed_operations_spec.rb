require 'rails_helper'

RSpec.describe JrcRelationship::WithdrawalReadiness do
  let(:account) { create(:account) }
  let(:manager) { create(:user, account: account, role: :administrator) }
  let(:analyst) { create(:user, account: account, role: :administrator) }
  let(:manager_member) { account.account_users.find_by!(user: manager) }
  let(:analyst_member) { account.account_users.find_by!(user: analyst) }
  let(:manager_context) { JrcRelationship::Context.new(manager_member.reload) }
  let(:analyst_context) { JrcRelationship::Context.new(analyst_member.reload) }
  let(:allocation) { JrcRelationship::Assignment.create!(account: account, owner: manager, contact: create(:contact, account: account)) }
  let(:input) do
    { 'operation' => 'activity', 'ids' => [allocation.id], 'title' => 'Synthetic pending reviewed activity',
      'due_at' => 1.day.from_now.iso8601, 'request_id' => SecureRandom.uuid }
  end
  let(:review) { JrcRelationship::ReviewedPortfolioBatch.new(analyst_context).preview(input) }
  let(:manager_role) do
    account.custom_roles.create!(name: 'Synthetic native scoped supervisor',
                                 permissions: %w[contact_manage jrc_relationship_view jrc_relationship_manage
                                                 jrc_relationship_team jrc_relationship_configure])
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'counts pending reviewed intentions even when the analyst owns no active allocation or other responsibility' do
    review
    result = described_class.new(manager_context).call(analyst.id)
    expect(result.fetch(:counts).fetch('reviewed_batches')).to eq(1)
    expect(result.fetch(:counts).except('reviewed_batches').values).to all(eq(0))
    expect(result.fetch(:can_withdraw_relationship)).to be(false)
    expect do
      JrcRelationship::AnalystWithdrawal.new(manager_context).call(analyst.id, reason: 'Synthetic final eligibility review',
                                                                               snapshot_digest: result.fetch(:snapshot_digest))
    end.to raise_error(ArgumentError, /Pending responsibilities/)
    expect(analyst_member.reload.jrc_relationship_withdrawn_at).to be_nil
  end

  it 'requires a fresh readiness review after the actor stops their own pending work and preserves all other account accesses' do
    saved = review
    record = JrcRelationship::BatchReview.find(saved.fetch('id'))
    pinned = record.attributes.slice('inputs', 'snapshot', 'digest')
    member_before = analyst_member.attributes.except('updated_at', 'jrc_relationship_withdrawn_at', 'jrc_relationship_eligibility_version')
    before = described_class.new(manager_context).call(analyst.id)
    JrcRelationship::ReviewedBatchInventory.new(analyst_context).cancel_pending(record.id, expected_revision: 1,
                                                                                           reason: 'Stop my own pending intentions')
    after = described_class.new(manager_context).call(analyst.id)
    expect(after.fetch(:counts).fetch('reviewed_batches')).to eq(0)
    expect do
      JrcRelationship::AnalystWithdrawal.new(manager_context).call(analyst.id, reason: 'Stale review',
                                                                               snapshot_digest: before.fetch(:snapshot_digest))
    end.to raise_error(ActiveRecord::StaleObjectError)
    result = JrcRelationship::AnalystWithdrawal.new(manager_context).call(analyst.id, reason: 'Current complete CS review',
                                                                                      snapshot_digest: after.fetch(:snapshot_digest))
    expect(result).to include(scope: 'relationship')
    expect(analyst_member.reload.jrc_relationship_withdrawn_at).to be_present
    expect([analyst_member.attributes.except('updated_at', 'jrc_relationship_withdrawn_at', 'jrc_relationship_eligibility_version'),
            JrcOperations::Access.crm?(analyst_member), record.reload.attributes.slice('inputs', 'snapshot', 'digest')])
      .to eq([member_before, true, pinned])
  end

  it 'refuses an inventory outside the supervisor current native allocation scope instead of reporting a misleading zero' do
    outside = create(:user, account: account, role: :agent)
    allocation.update!(owner: outside)
    review
    manager_member.update!(role: :agent, custom_role: manager_role)
    team = create(:team, account: account)
    [manager, analyst].each { |user| TeamMember.create!(team: team, user: user) }
    expect(manager_context.assignments.where(id: allocation.id)).not_to exist
    expect { described_class.new(manager_context).call(analyst.id) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'also preserves private named-portfolio metadata boundaries for a pending membership review' do
    owner = create(:user, account: account, role: :administrator)
    group = JrcRelationship::PortfolioGroup.create!(account: account, owner: owner, name: 'Private third-party coordinator portfolio')
    proposal = { 'operation' => 'portfolio_membership', 'ids' => [allocation.id], 'portfolio_group_id' => group.id,
                 'expected_version' => 0, 'active' => true, 'justification' => 'Native private scoped review', 'request_id' => SecureRandom.uuid }
    JrcRelationship::ReviewedPortfolioBatch.new(analyst_context).preview(proposal)
    manager_member.update!(role: :agent, custom_role: manager_role)
    team = create(:team, account: account)
    [manager, analyst].each { |user| TeamMember.create!(team: team, user: user) }
    expect(manager_context.assignments.where(id: allocation.id)).to exist
    expect(JrcRelationship::PortfolioGroupScope.resolve(manager_context).where(id: group.id)).not_to exist
    expect { described_class.new(manager_context).call(analyst.id) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'does not treat reviewed work in another account as a responsibility of the current account membership' do
    foreign = create(:account)
    foreign.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    membership = analyst.account_users.create!(account: foreign, role: :administrator)
    customer = JrcRelationship::Assignment.create!(account: foreign, owner: analyst, contact: create(:contact, account: foreign))
    other = JrcRelationship::ReviewedPortfolioBatch.new(JrcRelationship::Context.new(membership)).preview(
      input.merge('ids' => [customer.id], 'request_id' => SecureRandom.uuid)
    )
    result = described_class.new(manager_context).call(analyst.id)
    expect(result.fetch(:counts).fetch('reviewed_batches')).to eq(0)
    expect(result.fetch(:can_withdraw_relationship)).to be(true)
    expect(JrcRelationship::BatchReview.find(other.fetch('id')).state).to eq('previewed')
    expect(membership.reload.jrc_relationship_withdrawn_at).to be_nil
  end

  it 'counts native pending company subjects without an allocation ID rather than reporting a false zero for analyst withdrawal' do
    company = account.master_companies.create!(name: 'Synthetic unallocated withdrawal customer')
    group = JrcRelationship::PortfolioGroup.create!(account: account, owner: manager, name: 'Synthetic pending master portfolio')
    proposal = { 'operation' => 'master_allocation', 'ids' => [company.id], 'portfolio_group_id' => group.id,
                 'expected_version' => 0, 'justification' => 'Native pending master allocation', 'request_id' => SecureRandom.uuid,
                 'creations' => [{ 'company_id' => company.id, 'owner_id' => manager.id }] }
    saved = JrcRelationship::ReviewedPortfolioBatch.new(analyst_context).preview(proposal)
    result = described_class.new(manager_context).call(analyst.id)
    expect(result.fetch(:counts).fetch('reviewed_batches')).to eq(1)
    expect(result.fetch(:can_withdraw_relationship)).to be(false)
    expect(JrcRelationship::BatchReview.find(saved.fetch('id')).items.pluck(:assignment_id)).to eq([nil])
  end

  it 'denies a pending master audience hidden by native named-portfolio metadata rather than treating its nullable subject as visible' do
    company = account.master_companies.create!(name: 'Synthetic private master withdrawal customer')
    owner = create(:user, account: account, role: :administrator)
    group = JrcRelationship::PortfolioGroup.create!(account: account, owner: owner, name: 'Synthetic private master group')
    proposal = { 'operation' => 'master_allocation', 'ids' => [company.id], 'portfolio_group_id' => group.id,
                 'expected_version' => 0, 'justification' => 'Native private master review', 'request_id' => SecureRandom.uuid,
                 'creations' => [{ 'company_id' => company.id, 'owner_id' => owner.id }] }
    JrcRelationship::ReviewedPortfolioBatch.new(analyst_context).preview(proposal)
    manager_member.update!(role: :agent, custom_role: manager_role)
    team = create(:team, account: account)
    [manager, analyst].each { |user| TeamMember.create!(team: team, user: user) }
    expect { described_class.new(manager_context).call(analyst.id) }.to raise_error(Pundit::NotAuthorizedError)
  end
end
