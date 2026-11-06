require 'rails_helper'

RSpec.describe JrcRelationship::WithdrawalNativeLinks do
  include_context 'JRC Service Desk domain'
  let(:analyst) { create(:user, account: sd_account, role: :administrator) }
  let(:member) { sd_account.account_users.find_by!(user: analyst) }
  let(:context) { JrcRelationship::Context.new(sd_account_user) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: sd_account, owner: sd_user, contact: sd_contact) }
  let(:project) do
    JrcProjects::Projects::Create.call(account: sd_account, actor: analyst,
                                       attributes: { name: 'Synthetic origin-only project', visibility: 'private', contact_id: sd_contact.id },
                                       idempotency_key: SecureRandom.uuid)
  end
  let(:task) do
    JrcProjects::Tasks::Create.call(account_user: member, project: project,
                                    attributes: { title: 'Synthetic origin-only task', assignee_id: analyst.id }, correlation_id: SecureRandom.uuid)
  end
  let(:membership) { create(:jrc_sd_membership, unit: sd_unit, account_user: member) }
  let(:ticket) { sd_ticket(assignee_membership: membership, title: 'Synthetic origin-only ticket') }

  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm', 'jrc_projects')
  end

  it 'withdraws only CS eligibility while unrelated native ownership, records and source access stay intact' do
    records = [project, task, ticket]
    original = records.map(&:attributes)
    review = JrcRelationship::WithdrawalReadiness.new(context).call(analyst.id)
    expect(review.fetch(:counts)).to include('projects' => 0, 'project_tasks' => 0, 'service_tickets' => 0)
    result = JrcRelationship::AnalystWithdrawal.new(context).call(analyst.id, reason: 'Synthetic CS-only withdrawal',
                                                                              snapshot_digest: review.fetch(:snapshot_digest))
    expect(result).to include(state: 'withdrawn', account_membership_preserved: true)
    expect(records.map { |row| row.reload.attributes }).to eq(original)
    expect(JrcOperations::Access.projects(member).exists?(id: project.id)).to be(true)
    expect(JrcOperations::Access.tickets(member).exists?(id: ticket.id)).to be(true)
    expect { JrcRelationship::Context.new(member) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'still blocks withdrawal for active plan projects, their native tasks and explicit ticket commitments' do
    task
    JrcRelationship::SuccessPlan.create!(account: sd_account, assignment: assignment, owner: sd_user, project: project,
                                         title: 'Synthetic linked CS plan', goals: [{ 'metric' => 'Delivery', 'ticket_id' => ticket.id }])
    review = JrcRelationship::WithdrawalReadiness.new(context).call(analyst.id)
    expect(review.fetch(:counts)).to include('projects' => 1, 'project_tasks' => 1, 'service_tickets' => 1)
    expect do
      JrcRelationship::AnalystWithdrawal.new(context).call(analyst.id, reason: 'Synthetic incomplete CS handoff',
                                                                       snapshot_digest: review.fetch(:snapshot_digest))
    end.to raise_error(ArgumentError, /Pending responsibilities/)
    expect(member.reload.jrc_relationship_withdrawn_at).to be_nil
  end

  it 'includes pending native sources captured by an active CS action rather than only plan fields' do
    JrcRelationship::Action.create!(account: sd_account, assignment: assignment, owner: sd_user, kind: 'manual',
                                    reason: 'Synthetic active source evidence', source_key: SecureRandom.uuid,
                                    metadata: { '_source_ids' => {
                                      'projects' => [project.id], 'project_tasks' => [task.id], 'tickets' => [ticket.id]
                                    } })
    review = JrcRelationship::WithdrawalReadiness.new(context).call(analyst.id)
    expect(review.fetch(:counts)).to include('projects' => 1, 'project_tasks' => 1, 'service_tickets' => 1)
  end

  it 'includes the native project parent of a task commitment even without a direct project field' do
    JrcRelationship::SuccessPlan.create!(account: sd_account, assignment: assignment, owner: sd_user,
                                         title: 'Synthetic task-only link',
                                         metadata: { 'milestones' => [{ 'title' => 'Delivery', 'task_id' => task.id }] })
    review = JrcRelationship::WithdrawalReadiness.new(context).call(analyst.id)
    expect(review.fetch(:counts)).to include('projects' => 1, 'project_tasks' => 1)
  end

  it 'does not require native transfer just because a completed CS plan contains a historical reference' do
    JrcRelationship::SuccessPlan.create!(account: sd_account, assignment: assignment, owner: sd_user, project: project,
                                         title: 'Synthetic historical link', status: 'completed',
                                         goals: [{ 'metric' => 'Finished', 'task_id' => task.id, 'ticket_id' => ticket.id }])
    review = JrcRelationship::WithdrawalReadiness.new(context).call(analyst.id)
    expect(review.fetch(:counts)).to include('projects' => 0, 'project_tasks' => 0, 'service_tickets' => 0)
    expect(review.fetch(:can_withdraw_relationship)).to be(true)
  end

  it 'denies a hidden active CS origin instead of reporting its linked native work as unrelated or zero' do
    other = create(:user, account: sd_account, role: :administrator)
    hidden = JrcRelationship::Assignment.create!(account: sd_account, owner: other, contact: create(:contact, account: sd_account))
    JrcRelationship::SuccessPlan.create!(account: sd_account, assignment: hidden, owner: other, project: project, title: 'Synthetic hidden CS origin')
    role = create(:custom_role, account: sd_account, permissions: %w[contact_manage jrc_relationship_view jrc_relationship_team])
    sd_account_user.update!(role: :agent, custom_role: role)
    limited = JrcRelationship::Context.new(sd_account_user)
    expect { JrcRelationship::WithdrawalReadiness.new(limited).call(analyst.id) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'does not adopt a foreign account plan as a local native responsibility link' do
    foreign = create(:account)
    foreign.enable_features!('jrc_customer_master', 'jrc_relationship')
    owner = create(:user, account: foreign, role: :administrator)
    root = JrcRelationship::Assignment.create!(account: foreign, owner: owner, contact: create(:contact, account: foreign))
    JrcRelationship::SuccessPlan.create!(account: foreign, assignment: root, owner: owner, title: 'Foreign synthetic reference',
                                         goals: [{ 'metric' => 'Foreign reference', 'task_id' => task.id, 'ticket_id' => ticket.id }])
    review = JrcRelationship::WithdrawalReadiness.new(context).call(analyst.id)
    expect(review.fetch(:counts)).to include('projects' => 0, 'project_tasks' => 0, 'service_tickets' => 0)
  end

  it 'does not require source-module privileges for unrelated native responsibilities' do
    [project, task, ticket]
    role = create(:custom_role, account: sd_account,
                                permissions: %w[contact_manage jrc_relationship_view jrc_relationship_manage jrc_relationship_team
                                                jrc_relationship_configure])
    sd_account_user.update!(role: :agent, custom_role: role, jrc_projects_enabled: false)
    team = create(:team, account: sd_account)
    [sd_user, analyst].each { |user| team.team_members.create!(user: user) }
    limited = JrcRelationship::Context.new(sd_account_user)
    review = JrcRelationship::WithdrawalReadiness.new(limited).call(analyst.id)
    expect(review).to include(can_withdraw_relationship: true)
    expect(review.fetch(:counts)).to include('projects' => 0, 'project_tasks' => 0, 'service_tickets' => 0)
  end

  it 'rejects an earlier zero-workload review when a native project becomes linked to an active CS plan' do
    project
    review = JrcRelationship::WithdrawalReadiness.new(context).call(analyst.id)
    JrcRelationship::SuccessPlan.create!(account: sd_account, assignment: assignment, owner: sd_user, project: project,
                                         title: 'Synthetic newly linked CS commitment')
    expect do
      JrcRelationship::AnalystWithdrawal.new(context).call(analyst.id, reason: 'Synthetic stale scope review',
                                                                       snapshot_digest: review.fetch(:snapshot_digest))
    end.to raise_error(ActiveRecord::StaleObjectError)
    expect(member.reload.jrc_relationship_withdrawn_at).to be_nil
  end

  it 'retains a pending implementation project origin recorded by the native CS handoff' do
    JrcRelationship::Action.create!(account: sd_account, assignment: assignment, owner: sd_user, kind: 'onboarding',
                                    reason: 'Synthetic handoff source', source_key: 'handoff',
                                    metadata: { 'source_type' => 'JrcProjects::Project', 'source_id' => project.id })
    review = JrcRelationship::WithdrawalReadiness.new(context).call(analyst.id)
    expect(review.fetch(:counts).fetch('projects')).to eq(1)
  end

  it 'recognizes native post-ticket follow-up origins even before a source manifest was captured' do
    JrcRelationship::Action.create!(account: sd_account, assignment: assignment, owner: sd_user, kind: 'post_ticket',
                                    reason: 'Synthetic native post-ticket origin', source_key: "post-ticket:#{ticket.id}:synthetic")
    review = JrcRelationship::WithdrawalReadiness.new(context).call(analyst.id)
    expect(review.fetch(:counts).fetch('service_tickets')).to eq(1)
  end
end
