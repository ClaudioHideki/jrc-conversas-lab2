require 'rails_helper'

RSpec.describe JrcRelationship::CadenceActionBudget do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: actor)) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact, inbox: inbox) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: contact) }
  let(:configuration) { JrcRelationship::Configuration.create!(account: account, rules: { automatic_action_daily_limit: 1 }) }
  let(:book) do
    JrcRelationship::Playbook.create!(account: account, name: 'Synthetic governed cadence', active: true, trigger_kind: 'no_contact',
                                      steps: [{ 'kind' => 'action', 'title' => 'Synthetic first work', 'after_days' => 0 },
                                              { 'kind' => 'action', 'title' => 'Synthetic second work', 'after_days' => 0 }])
  end
  let(:enrollment) do
    configuration
    service = JrcRelationship::ReviewedPortfolioBatch.new(context)
    input = { 'ids' => [assignment.id], 'operation' => 'cadence', 'playbook_id' => book.id,
              'conversation_id' => conversation.display_id, 'starts_at' => Time.current.iso8601(6), 'request_id' => SecureRandom.uuid }
    review = service.preview(input)
    service.approve(review.fetch('id'), digest: review.fetch('digest'))
    service.advance(review.fetch('id'))
    JrcRelationship::CadenceEnrollment.find_by!(account: account, batch_review_id: review.fetch('id'))
  end
  let(:service) { JrcRelationship::ReviewedCadence.new(context) }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'persists a truthful pending step with no receipt or revision change, deduplicates deferral and resumes at the next account day' do
    travel_to(Time.utc(2026, 11, 5, 23, 30)) do
      id = enrollment.id
      frozen = enrollment.snapshot.deep_dup
      service.advance(id)
      2.times { service.advance(id) }
      expected = Time.utc(2026, 11, 6, 3)
      expect(Time.iso8601(service.get(id).fetch('retry_at'))).to eq(expected)
      expect(enrollment.steps.order(:ordinal).pluck(:state, :receipt)).to match([['applied', be_a(Hash)], ['pending', nil]])
      expect([assignment.actions.count, enrollment.reload.revision]).to eq([1, 2])
      events = JrcCrm::AuditEvent.where(account: account, resource_type: enrollment.class.name, resource_id: id)
                                 .where("metadata ->> 'action' = 'cadence_budget_deferred'")
      expect(events.count).to eq(1)
      travel_to(expected)
      expect(service.advance(id)).to include('state' => 'completed', 'retry_at' => nil)
      expect(assignment.actions.order(:id).map { |action| action.metadata.fetch('automatic') }).to eq([true, true])
      expect(enrollment.reload.snapshot).to eq(frozen)
    end
  end

  it 'schedules the next worker attempt at the persisted budget boundary instead of spinning on the old due time' do
    travel_to(Time.utc(2026, 11, 5, 23, 30)) do
      id = enrollment.id
      service.advance(id)
      expect { JrcRelationship::CadenceExecutionJob.perform_now(id) }
        .to have_enqueued_job(JrcRelationship::CadenceExecutionJob).with(id).at(Time.utc(2026, 11, 6, 3))
      expect(enrollment.steps.order(:ordinal).pluck(:state)).to eq(%w[applied pending])
      expect(assignment.actions.count).to eq(1)
    end
  end

  it 'rechecks a real customer reply during deferral and cancels remaining work instead of executing it' do
    id = enrollment.id
    service.advance(id)
    service.advance(id)
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :incoming, sender: contact)
    expect(service.advance(id)).to include('state' => 'stopped', 'stop_reason' => 'CONTACT_REPLIED', 'retry_at' => nil)
    expect(enrollment.steps.order(:ordinal).pluck(:state)).to eq(%w[applied canceled])
    expect(assignment.actions.count).to eq(1)
  end

  it 'stops the deferred enrollment when native module authority is revoked and preserves already committed work' do
    id = enrollment.id
    service.advance(id)
    service.advance(id)
    account.disable_features!('jrc_relationship')
    JrcRelationship::CadenceExecutionJob.perform_now(id)
    expect(enrollment.reload).to have_attributes(state: 'stopped', stop_reason: 'AUTHORITY_REVOKED')
    expect(assignment.actions.count).to eq(1)
    expect(enrollment.steps.order(:ordinal).pluck(:state)).to eq(%w[applied canceled])
  end

  it 'leaves the approved legacy schedule unlimited when the account limit is disabled' do
    configuration.update!(rules: { automatic_action_daily_limit: 0 })
    id = enrollment.id
    2.times { service.advance(id) }
    expect(enrollment.reload.state).to eq('completed')
    expect(assignment.actions.count).to eq(2)
    expect(service.get(id).fetch('retry_at')).to be_nil
  end

  it 'budgets actual Agenda activities and meetings without a partial CRM record or duplicate receipt' do
    travel_to(Time.utc(2026, 11, 5, 23, 30)) do
      book.update!(steps: [{ 'kind' => 'activity', 'title' => 'Synthetic Agenda task', 'after_days' => 0 },
                           { 'kind' => 'meeting', 'title' => 'Synthetic Agenda meeting', 'after_days' => 0 }])
      id = enrollment.id
      service.advance(id)
      expect(service.advance(id)).to include('state' => 'active', 'retry_reason' => 'account_daily_budget')
      expect(account.jrc_crm_activities.pluck(:activity_type)).to eq(['task'])
      expect(enrollment.steps.order(:ordinal).pluck(:state)).to eq(%w[applied pending])
      travel_to(Time.utc(2026, 11, 6, 3))
      2.times { service.advance(id) }
      expect(account.jrc_crm_activities.order(:id).pluck(:activity_type)).to eq(%w[task meeting])
      expect(assignment.actions.order(:id).map { |action| action.metadata.fetch('automatic') }).to eq([true, true])
      expect(enrollment.reload.state).to eq('completed')
    end
  end

  it 'rolls back unavailable automatic Agenda work, persists one waiting state and resumes only with an available native owner' do
    assignment
    configuration.update!(rules: { automatic_action_daily_limit: 1, portfolio_capacity_limits: [
                            { user_id: actor.id, maximum: 10, availability: 0, dedication: 1 }
                          ] })
    book.update!(steps: [{ 'kind' => 'activity', 'title' => 'Synthetic deferred Agenda work', 'after_days' => 0 }])
    id = enrollment.id
    expect(service.advance(id)).to include('state' => 'active', 'retry_reason' => 'native_assignment_unavailable')
    expect([assignment.actions.count, account.jrc_crm_activities.count, JrcOperations::Queue.where(account: account).count]).to eq([0, 0, 0])
    expect(enrollment.steps.pluck(:state, :receipt)).to eq([['pending', nil]])
    travel 6.minutes do
      service.advance(id)
      expect(Time.iso8601(service.get(id).fetch('retry_at'))).to be > Time.current
    end
    events = JrcCrm::AuditEvent.where(account: account, resource_type: enrollment.class.name, resource_id: id)
                               .where("metadata ->> 'action' = 'cadence_assignment_deferred'")
    expect(events.count).to eq(1)
    configuration.update!(version: 2, rules: { automatic_action_daily_limit: 1, portfolio_capacity_limits: [
                            { user_id: actor.id, maximum: 10, availability: 1, dedication: 1 }
                          ] })
    service.advance(id)
    expect([enrollment.reload.state, assignment.actions.count, account.jrc_crm_activities.count]).to eq(['completed', 1, 1])
  end

  it 'cancels unavailable Agenda work after a genuine customer reply with no task created by an earlier failed attempt' do
    assignment
    configuration.update!(rules: { automatic_action_daily_limit: 1, portfolio_capacity_limits: [
                            { user_id: actor.id, maximum: 10, availability: 0, dedication: 1 }
                          ] })
    book.update!(steps: [{ 'kind' => 'meeting', 'title' => 'Synthetic unavailable meeting', 'after_days' => 0 }])
    id = enrollment.id
    service.advance(id)
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :incoming, sender: contact)
    expect(service.advance(id)).to include('state' => 'stopped', 'stop_reason' => 'CONTACT_REPLIED')
    expect([assignment.actions.count, account.jrc_crm_activities.count]).to eq([0, 0])
    expect(enrollment.steps.pluck(:state, :receipt)).to eq([['canceled', nil]])
  end

  it 'preserves an explicit authorized manual Agenda owner without marking their work as an automatic quota effect' do
    assignment
    configuration.update!(rules: { portfolio_capacity_limits: [{ user_id: actor.id, maximum: 10, availability: 0, dedication: 1 }] })
    activity = JrcRelationship::Workflow.new(context).activity!(assignment: assignment, title: 'Synthetic explicit manual Agenda task',
                                                                due_at: 1.day.from_now, request_id: SecureRandom.uuid, owner_id: actor.id)
    expect(activity).to be_persisted
    expect(activity.user_id).to eq(actor.id)
    expect(assignment.actions.first.metadata['automatic']).not_to be(true)
    expect(JrcRelationship::CadenceEnrollment.where(account: account)).to be_empty
  end
end
