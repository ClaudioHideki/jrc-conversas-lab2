require 'rails_helper'
require Rails.root.join('db/migrate/20260929140000_create_independent_jrc_projects')
require Rails.root.join('db/migrate/20260929140100_create_r2_project_links')
require Rails.root.join('db/migrate/20260929140200_enforce_r2_project_link_scope')

RSpec.describe 'P1-P3 additive migration reversibility', type: :model do
  it 'round trips only the new tables while preserving R2 records, flags and memberships' do
    account = create(:account)
    account.enable_features!('jrc_service_desk', 'jrc_broker', 'jrc_flows')
    user = create(:user, account: account, role: :administrator)
    unit = create(:jrc_sd_unit, operator_company: create(:jrc_sd_operator_company, account: account))
    membership = create(:jrc_sd_membership, unit: unit, account_user: account.account_users.find_by!(user: user))
    ticket = create(:jrc_sd_ticket, unit: unit, created_by_membership: membership)
    original = ticket.attributes
    flags = account.reload.feature_flags_ext_1
    migrations = [CreateIndependentJrcProjects, CreateR2ProjectLinks, EnforceR2ProjectLinkScope]
    migrations.reverse_each { |migration| migration.new.migrate(:down) }
    expect(ActiveRecord::Base.connection.table_exists?(:jrc_projects_projects)).to be(false)
    expect(JrcServiceDesk::Ticket.find(ticket.id).attributes).to eq(original)
    migrations.each { |migration| migration.new.migrate(:up) }
    AccountUser.reset_column_information
    expect(account.reload.feature_flags_ext_1).to eq(flags)
    expect(account.feature_enabled?('jrc_projects')).to be(false)
    expect(account.account_users.where(jrc_projects_enabled: true)).to be_empty
    expect(JrcServiceDesk::Ticket.find(ticket.id).attributes).to eq(original)
    expect(JrcServiceDesk::UnitMembership.find(membership.id).active).to be(true)
    expect(ActiveRecord::Base.connection.foreign_keys(:jrc_operations_links).map(&:name)).to include('fk_project_links_r2_unit')
  ensure
    AccountUser.reset_column_information
  end
end
