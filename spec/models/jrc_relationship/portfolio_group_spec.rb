require 'rails_helper'

RSpec.describe JrcRelationship::PortfolioGroup do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:analyst) { create(:user, account: account, role: :agent) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:group) { described_class.create!(account: account, owner: actor, name: 'Synthetic named portfolio') }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: analyst)) }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'links one existing allocation to multiple active named portfolios without duplicating or transferring the customer' do
    original = assignment.attributes
    second = described_class.create!(account: account, owner: actor, name: 'Synthetic second portfolio')
    expect do
      [group, second].each do |portfolio|
        JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: portfolio, assignment: assignment)
      end
    end.not_to change(JrcRelationship::Assignment, :count)
    expect(assignment.reload.attributes).to eq(original)
    expect(JrcRelationship::PortfolioGroupAssignment.where(account: account, assignment: assignment, active: true).count).to eq(2)
  end

  it 'deduplicates a customer within each portfolio while keeping inactive links for history' do
    link = JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: group, assignment: assignment)
    link.update!(active: false)
    duplicate = JrcRelationship::PortfolioGroupAssignment.new(account: account, portfolio_group: group, assignment: assignment)
    expect(duplicate).not_to be_valid
    expect(link.reload).to have_attributes(active: false, assignment_id: assignment.id)
  end

  it 'applies current metadata privacy without granting the grouped customer to another analyst' do
    group.update!(visibility: 'account')
    JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: group, assignment: assignment)
    expect(JrcRelationship::PortfolioGroupScope.resolve(context)).to exist(id: group.id)
    expect(context.assignments).not_to exist(id: assignment.id)
    group.update!(visibility: 'private')
    expect(JrcRelationship::PortfolioGroupScope.resolve(context)).not_to exist(id: group.id)
  end

  it 'uses existing team membership only for team metadata visibility and creates no team grant' do
    team = create(:team, account: account)
    group.update!(visibility: 'team', team: team)
    expect(JrcRelationship::PortfolioGroupScope.resolve(context)).not_to exist(id: group.id)
    create(:team_member, team: team, user: analyst)
    expect(JrcRelationship::PortfolioGroupScope.resolve(context)).to exist(id: group.id)
    expect(context.assignments).not_to exist(id: assignment.id)
  end

  it 'requires explicit finite goal measurements instead of converting units or inventing defaults' do
    group.goals = [{ 'metric' => 'Customer contact coverage', 'target' => 80, 'current' => 65, 'unit' => 'percent' }]
    expect(group).to be_valid
    group.goals = [{ 'metric' => 'Invalid', 'target' => '80', 'formula' => 'invented' }]
    expect(group).not_to be_valid
  end

  it 'blocks new or reactivated coordination for a withdrawn analyst while preserving archived references' do
    group.update!(status: 'archived')
    account.account_users.find_by!(user: actor).update!(jrc_relationship_withdrawn_at: Time.current)
    expect(group.reload).to be_valid
    group.status = 'active'
    expect(group).not_to be_valid
    expect(described_class.new(account: account, owner: actor, name: 'New withdrawn coordination')).not_to be_valid
  end

  it 'keeps active group coordination in CS withdrawal readiness until it is archived or transferred' do
    group
    admin = create(:user, account: account, role: :administrator)
    viewer = JrcRelationship::Context.new(account.account_users.find_by!(user: admin))
    before = JrcRelationship::WithdrawalReadiness.new(viewer).call(actor.id)
    expect(before.fetch(:counts)).to include('portfolio_groups' => 1)
    expect(before.fetch(:can_withdraw_relationship)).to be(false)
    group.update!(status: 'archived')
    after = JrcRelationship::WithdrawalReadiness.new(viewer).call(actor.id)
    expect(after.fetch(:counts)).to include('portfolio_groups' => 0)
    expect(after.fetch(:state)).to eq('ready_for_final_review')
  end

  it 'enforces cross-account customer references in PostgreSQL even when model validation is bypassed' do
    foreign = create(:account)
    other = JrcRelationship::Assignment.create!(account: foreign, contact: create(:contact, account: foreign))
    connection = ActiveRecord::Base.connection
    expect do
      JrcRelationship::PortfolioGroupAssignment.transaction(requires_new: true) do
        connection.execute('INSERT INTO jrc_relationship_portfolio_group_assignments ' \
                           '(account_id,portfolio_group_id,assignment_id,active,created_at,updated_at) ' \
                           "VALUES (#{account.id},#{group.id},#{other.id},true,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)")
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(group.customer_links).to be_empty
  end
end
