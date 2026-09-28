# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk::TicketPolicy do
  include_context 'JRC Service Desk domain'

  it 'permits an agent to read a ticket they created in an explicitly granted unit' do
    expect(described_class.new(sd_context, sd_ticket).show?).to be(true)
  end

  it 'denies a ticket in another Account even for an administrator' do
    sd_as_admin!
    ticket = create(:jrc_sd_ticket, unit: sd_foreign_unit)
    expect(described_class.new(sd_context, ticket).show?).to be(false)
  end

  it 'denies a ticket in an ungranted unit of the same Account even for administrator' do
    sd_as_admin!
    ticket = create(:jrc_sd_ticket, unit: sd_other_unit)
    expect(described_class.new(sd_context, ticket).show?).to be(false)
    expect(described_class::Scope.new(sd_context, JrcServiceDesk::Ticket).resolve).not_to include(ticket)
  end

  it 'denies a known ticket ID after unit grant revocation' do
    ticket = sd_ticket
    sd_membership.update!(active: false)
    expect(described_class.new(sd_context, ticket).show?).to be(false)
  end

  it 'denies a same-unit ticket unrelated to the agent, their assignment or team' do
    creator = create(:jrc_sd_membership, unit: sd_unit)
    ticket = sd_ticket(created_by_membership: creator)
    expect(described_class.new(sd_context, ticket).show?).to be(false)
  end

  it 'permits an assigned ticket only inside an explicitly granted unit' do
    creator = create(:jrc_sd_membership, unit: sd_unit)
    ticket = sd_ticket(created_by_membership: creator, assignee_membership: sd_membership)
    expect(described_class.new(sd_context, ticket).show?).to be(true)
  end

  it 'uses native teams only as a restriction within the unit boundary' do
    creator = create(:jrc_sd_membership, unit: sd_unit)
    team = create(:team, account: sd_account)
    create(:team_member, team: team, user: sd_user)
    own_scope_ticket = sd_ticket(created_by_membership: creator, team: team)
    wrong_unit_ticket = create(:jrc_sd_ticket, unit: sd_other_unit, team: team)
    rows = described_class::Scope.new(sd_context, JrcServiceDesk::Ticket).resolve
    expect(rows).to include(own_scope_ticket)
    expect(rows).not_to include(wrong_unit_ticket)
  end

  it 'keeps feature-off policy scopes empty' do
    ticket = sd_ticket
    sd_account.disable_features!('jrc_service_desk')
    expect(described_class.new(sd_context, ticket).show?).to be(false)
    expect(described_class::Scope.new(sd_context, JrcServiceDesk::Ticket).resolve).to be_empty
  end

  it 'does not grant transition or destruction through a generic update policy' do
    policy = described_class.new(sd_context, sd_ticket)
    expect(policy.transition?).to be(false)
    expect(policy.destroy?).to be(false)
  end
end
