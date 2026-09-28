# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'CP5 dashboard scope and capabilities' do
  include_context 'JRC Service Desk domain'

  it 'uses legitimately different unit scopes for different native users' do
    sd_as_admin!
    visible = sd_ticket
    hidden = create(:jrc_sd_ticket, unit: sd_other_unit)
    foreign = create(:jrc_sd_ticket, unit: sd_foreign_unit)
    other_user = create(:user)
    other_au = create(:account_user, account: sd_account, user: other_user, role: :administrator)
    create(:jrc_sd_membership, unit: sd_other_unit, account_user: other_au)
    first = JrcServiceDesk::DashboardService.new(user_context: sd_context).call
    second_context = { account: sd_account, user: other_user, account_user: other_au }
    second = JrcServiceDesk::DashboardService.new(user_context: second_context).call
    expect(first[:total]).to eq(1)
    expect(second[:total]).to eq(1)
    [first, second].each do |result|
      expect(result[:total]).to eq(result[:phases].values.sum)
      expect(result[:active]).to eq(result[:phases]['open'] + result[:phases]['waiting'])
    end
    expect(JrcServiceDesk::TicketPolicy::Scope.new(sd_context, JrcServiceDesk::Ticket).resolve.pluck(:id)).to eq([visible.id])
    expect(JrcServiceDesk::TicketPolicy::Scope.new(second_context, JrcServiceDesk::Ticket).resolve.pluck(:id)).to eq([hidden.id])
    expect(first[:by_status].map { |r| r[:id] }).not_to include(foreign.status_id.to_s)
  end

  it 'does not infer dashboard capability from ticket read permission' do
    skip 'Native CustomRole extension unavailable' unless defined?(::CustomRole) && sd_account_user.respond_to?(:custom_role)
    role = CustomRole.create!(account: sd_account, name: 'Ticket read only', permissions: %w[jrc_service_desk_module_view jrc_service_desk_tickets_view])
    sd_account_user.update!(custom_role: role)
    sd_ticket
    expect { JrcServiceDesk::DashboardService.new(user_context: sd_context).call }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcServiceDesk::TicketQuery.new(user_context: sd_context).collection[:meta][:total]).to eq(1)
  end
end
