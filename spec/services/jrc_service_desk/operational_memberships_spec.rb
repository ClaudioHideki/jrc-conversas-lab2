# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk operational membership management' do
  include_context 'JRC Service Desk domain'
  let(:target) { create(:account_user, account: sd_account, role: :agent, auto_assignment_enabled: false) }
  let(:team) { create(:team, account: sd_account) }
  let(:queue) { create(:jrc_sd_queue, unit: sd_unit, team: team) }
  let(:service) { JrcServiceDesk::StructureService.new(user_context: sd_context) }

  before { sd_as_admin! }

  it 'adds and edits an existing internal account membership with real fields and an audit without redistributing existing tickets' do
    existing = sd_ticket
    target
    user_count = User.count
    result = service.create(resource: 'unit_memberships', reason: 'Synthetic approved operational setup', idempotency_key: 'operator-create',
      attributes: { unit_id: sd_unit.id, account_user_id: target.id, active: true, manual_assignment_enabled: true,
                    availability: 'paused', capacity: 4, skills: ['billing'], team_id: team.id, queue_id: queue.id })
    expect(result.record).to have_attributes(manual_assignment_enabled: true, team_id: team.id, queue_id: queue.id,
                                             availability: 'paused', capacity: 4, skills: ['billing'])
    expect(User.count).to eq(user_count)
    expect(target.reload.auto_assignment_enabled?).to be(false)
    result = service.update(resource: 'unit_memberships', record_id: result.record.id, reason: 'Disable manual only',
      idempotency_key: 'operator-update', expected_revision: JrcServiceDesk::StructureRecords.revision('unit_memberships', result.record),
      attributes: { manual_assignment_enabled: false, availability: 'available' })
    expect(result.record.manual_assignment_enabled?).to be(false)
    expect(JSON.parse(Audited::Audit.find(result.audit_id).comment).dig('after', 'manual_assignment_enabled')).to be(false)
    expect(existing.reload.assignee_membership_id).to be_nil
    expect(existing.ticket_events).to be_empty
  end

  it 'keeps an administrative audit actor inactive and unavailable and rejects making it operational through management' do
    actor = JrcServiceDesk::UnitMembership.create!(account: sd_account, unit: sd_other_unit, account_user: sd_account_user,
      administrative_actor: true, active: false, availability: 'unavailable', capacity: nil, skills: [])
    expect do
      service.update(resource: 'unit_memberships', record_id: actor.id, reason: 'Attempted operational conversion',
        idempotency_key: 'audit-conversion', expected_revision: JrcServiceDesk::StructureRecords.revision('unit_memberships', actor),
        attributes: { active: true, availability: 'available' })
    end.to raise_error(Pundit::NotAuthorizedError)
    expect(actor.reload).to have_attributes(administrative_actor: true, active: false, availability: 'unavailable', capacity: nil, skills: [])
  end

  it 'denies implicit, mismatched, cross-unit and broad supervision grants' do
    target_membership = create(:jrc_sd_membership, unit: sd_unit, account_user: target)
    other_team = create(:team, account: sd_account)
    expect do
      target_membership.update!(restricted_supervision: true,
        supervision_grants: [{ queue_id: queue.id, team_id: other_team.id, permissions: ['tickets_view'] }])
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect do
      target_membership.update!(restricted_supervision: true,
        supervision_grants: [{ queue_id: queue.id, team_id: team.id, permissions: %w[tickets_view tickets_view_all] }])
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect do
      target_membership.update!(restricted_supervision: true,
        supervision_grants: [{ queue_id: nil, team_id: team.id, permissions: ['tickets_view'] }])
    end.to raise_error(ActiveRecord::RecordInvalid)
    foreign_queue = create(:jrc_sd_queue, unit: sd_other_unit, team: team)
    expect do
      target_membership.update!(restricted_supervision: true,
        supervision_grants: [{ queue_id: foreign_queue.id, team_id: team.id, permissions: ['tickets_view'] }])
    end.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'filters activation, AutoAssign, presence, team and queue before server pagination and reports actual workload' do
    membership = create(:jrc_sd_membership, unit: sd_unit, account_user: target, team: team, queue: queue,
      availability: 'available', capacity: 2)
    target.update!(availability: :online)
    sd_ticket(assignee_membership: membership)
    allow(OnlineStatusTracker).to receive(:live_presence).with(sd_account.id).and_return(user_ids: [target.user_id], reason: nil)
    result = JrcServiceDesk::AssigneesDirectory.new(account: sd_account, parameters: {
      unit_id: sd_unit.id, team_id: team.id, queue_id: queue.id, active: 'true', auto_assignment_enabled: 'false', presence: 'online'
    }).call
    expect(result[:meta]).to include(total: 1, page: 1, per_page: 25)
    expect(result[:items].first).to include(id: membership.id.to_s, load: 1, effective_presence: true,
      auto_assignment_enabled: false, ineligibility_reason: 'agent_auto_assignment_disabled')
  end

  it 'shows a live heartbeat independently of native availability and an operational pause' do
    membership = create(:jrc_sd_membership, unit: sd_unit, account_user: target, team: team, queue: queue,
      availability: 'paused', capacity: 2)
    target.update!(availability: :busy, auto_assignment_enabled: true)
    allow(OnlineStatusTracker).to receive(:live_presence).with(sd_account.id).and_return(user_ids: [target.user_id], reason: nil)
    result = JrcServiceDesk::AssigneesDirectory.new(account: sd_account, parameters: {
      unit_id: sd_unit.id, team_id: team.id, queue_id: queue.id, presence: 'online'
    }).call

    expect(result[:meta]).to include(total: 1)
    expect(result[:items].first).to include(id: membership.id.to_s, effective_presence: true, configured_availability: 'busy',
      auto_assignment_enabled: true, ineligibility_reason: 'operational_unavailable')
    expect(result[:items].first.fetch(:record)).to include('availability' => 'paused')
  end

  it 'preserves explicit operation grants when the supervision SQL is embedded beside positional binds' do
    authorized = sd_ticket(queue: queue, team: team, title: 'Synthetic authorized history')
    sd_ticket(title: 'Synthetic outside department')
    sd_membership.update!(restricted_supervision: true,
      supervision_grants: [{ queue_id: queue.id, team_id: team.id, permissions: %w[tickets_view history_view] }])
    access = JrcServiceDesk::OperationalContext.new(sd_context).supervision_access
    source = access.scope(JrcServiceDesk::Ticket.where(account_id: sd_account.id), permission: 'history_view').select(:id).to_sql
    rows = JrcServiceDesk::Ticket.where("id IN (#{source}) AND title <> ?", 'Synthetic excluded title')
    expect(rows.pluck(:id)).to eq([authorized.id])

    sd_membership.update!(supervision_grants: [{ queue_id: queue.id, team_id: team.id, permissions: ['tickets_view'] }])
    source = access.scope(JrcServiceDesk::Ticket.where(account_id: sd_account.id), permission: 'history_view').select(:id).to_sql
    expect(JrcServiceDesk::Ticket.where("id IN (#{source}) AND title <> ?", 'Synthetic excluded title')).to be_empty
  end
end
