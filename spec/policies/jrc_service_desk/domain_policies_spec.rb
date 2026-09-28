# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk configuration, history and SLA policies' do
  include_context 'JRC Service Desk domain'

  it 'allows configuration reads but not writes to a normal agent' do
    policy = JrcServiceDesk::PriorityPolicy.new(sd_context, sd_priority)
    expect(policy.show?).to be(true)
    expect(policy.update?).to be(false)
  end

  it 'allows an administrator configuration only in explicitly granted units' do
    sd_as_admin!
    foreign_unit_priority = create(:jrc_sd_priority, unit: sd_other_unit)
    expect(JrcServiceDesk::PriorityPolicy.new(sd_context, sd_priority).update?).to be(true)
    expect(JrcServiceDesk::PriorityPolicy.new(sd_context, foreign_unit_priority).update?).to be(false)
  end

  it 'does not expose scope self-grant commands to administrator' do
    sd_as_admin!
    expect(JrcServiceDesk::UnitMembershipPolicy.new(sd_context, sd_membership).create?).to be(false)
    expect(JrcServiceDesk::UnitMembershipPolicy.new(sd_context, sd_membership).update?).to be(false)
  end

  it 'does not expose raw contract conditions to an agent who can read the ticket' do
    ticket = sd_ticket
    snapshot = create(:jrc_sd_snapshot, ticket: ticket)
    milestone = create(:jrc_sd_milestone, sla_snapshot: snapshot)
    expect(JrcServiceDesk::SlaSnapshotPolicy.new(sd_context, snapshot).show?).to be(false)
    expect(JrcServiceDesk::SlaSnapshotPolicy::Scope.new(sd_context, JrcServiceDesk::SlaSnapshot).resolve).to be_empty
    expect(JrcServiceDesk::SlaMilestonePolicy.new(sd_context, milestone).show?).to be(true)
  end

  it 'limits child records to authorized parent tickets' do
    ticket = create(:jrc_sd_ticket, unit: sd_other_unit)
    note = create(:jrc_sd_note, ticket: ticket)
    expect(JrcServiceDesk::TicketNotePolicy.new(sd_context, note).show?).to be(false)
    expect(JrcServiceDesk::TicketNotePolicy::Scope.new(sd_context, JrcServiceDesk::TicketNote).resolve).not_to include(note)
  end

  it 'does not expose unchecked conversation link lists' do
    expect(JrcServiceDesk::TicketConversationPolicy::Scope.new(sd_context, JrcServiceDesk::TicketConversation).resolve).to be_empty
  end

  it 'denies index permission without any active unit, including for administrator' do
    sd_as_admin!
    sd_membership.update!(active: false)
    [JrcServiceDesk::UnitPolicy, JrcServiceDesk::OperatorCompanyPolicy,
     JrcServiceDesk::TicketPolicy, JrcServiceDesk::PriorityPolicy,
     JrcServiceDesk::TicketNotePolicy, JrcServiceDesk::SlaSnapshotPolicy].each do |policy|
      expect(policy.new(sd_context, JrcServiceDesk::Ticket).index?).to be(false)
    end
  end

end
