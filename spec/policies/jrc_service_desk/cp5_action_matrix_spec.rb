# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'Service Desk native capability matrix' do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures

  def set_grants(*keys)
    skip 'Native CustomRole extension unavailable' unless defined?(::CustomRole) && sd_account_user.respond_to?(:custom_role)
    role = CustomRole.create!(account: sd_account, name: SecureRandom.hex(6), permissions: keys.flatten.map { |key| "jrc_service_desk_#{key}" })
    sd_account_user.update!(custom_role: role)
  end

  { update: 'tickets_edit', assign: 'tickets_assign', transfer: 'tickets_transfer', change_priority: 'priority_change',
    view_notes: 'notes_view', view_history: 'history_view', view_conversations: 'conversations_view', view_sla: 'sla_view' }.each do |action, key|
    it "requires the #{key} capability for #{action}, even with membership" do
      row = sd_ticket
      set_grants('module_view', 'tickets_view')
      expect(JrcServiceDesk::TicketPolicy.new(sd_context, row).public_send("#{action}?")).to be(false)
      set_grants('module_view', 'tickets_view', key)
      expect(JrcServiceDesk::TicketPolicy.new(sd_context, row).public_send("#{action}?")).to be(true)
      sd_membership.update!(active: false)
      expect(JrcServiceDesk::TicketPolicy.new(sd_context, row).public_send("#{action}?")).to be(false)
    end
  end

  it 'does not expose a foreign unit through view-all capability' do
    hidden = create(:jrc_sd_ticket, unit: sd_other_unit)
    set_grants('module_view', 'tickets_view', 'tickets_view_all')
    expect(JrcServiceDesk::TicketPolicy.new(sd_context, hidden).show?).to be(false)
  end

  it 'requires a separate capability for policy management' do
    row = JrcServiceDesk::LifecyclePolicy.new(account: sd_account, unit: sd_unit)
    set_grants('module_view', 'settings_view', 'lookups_view')
    expect(JrcServiceDesk::LifecyclePolicyPolicy.new(sd_context, row).publish?).to be(false)
    set_grants('module_view', 'settings_view', 'lookups_view', 'lifecycle_policies_manage')
    expect(JrcServiceDesk::LifecyclePolicyPolicy.new(sd_context, row).publish?).to be(true)
    foreign = JrcServiceDesk::LifecyclePolicy.new(account: sd_account, unit: sd_other_unit)
    expect(JrcServiceDesk::LifecyclePolicyPolicy.new(sd_context, foreign).publish?).to be(false)
  end

  it 'filters transition options by action capability without changing pinned rules' do
    lc_publish
    row = sd_ticket
    set_grants('module_view', 'tickets_view', 'sla_view', 'history_view', 'resolve')
    result = JrcServiceDesk::LifecycleReadService.new(user_context: sd_context, ticket: row).call
    expect(result[:options].map { |entry| entry[:action] }.uniq).to eq(['resolve'])
    expect(JrcServiceDesk::LifecycleActionPolicy.new(sd_context, row).action?('cancel')).to be(false)
  end
end
