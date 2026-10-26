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
    connection = ActiveRecord::Base.connection
    # Later modules reference Projects. Suspend their foreign keys only inside
    # this rolled-back test transaction to exercise the original P1-P3 boundary.
    later_keys = %i[jrc_relationship_success_plans jrc_service_desk_case_resource_links].flat_map do |table|
      connection.foreign_keys(table).select { |key| %w[jrc_projects_projects jrc_projects_tasks].include?(key.to_table) }
    end
    expect(later_keys.map(&:name)).to include('jrc_sd_case_resource_task')
    later_keys.each { |key| connection.remove_foreign_key(key.from_table, name: key.name) }
    migrations = [CreateIndependentJrcProjects, CreateR2ProjectLinks, EnforceR2ProjectLinkScope]
    migrations.reverse_each { |migration| migration.new.migrate(:down) }
    expect(ActiveRecord::Base.connection.table_exists?(:jrc_projects_projects)).to be(false)
    expect(JrcServiceDesk::Ticket.find(ticket.id).attributes).to eq(original)
    migrations.each { |migration| migration.new.migrate(:up) }
    later_keys.each { |key| connection.add_foreign_key(key.from_table, key.to_table, **key.options) }
    AccountUser.reset_column_information
    expect(account.reload.feature_flags_ext_1).to eq(flags)
    expect(account.feature_enabled?('jrc_projects')).to be(false)
    expect(account.account_users.where(jrc_projects_enabled: true)).to be_empty
    expect(JrcServiceDesk::Ticket.find(ticket.id).attributes).to eq(original)
    expect(JrcServiceDesk::UnitMembership.find(membership.id).active).to be(true)
    expect(ActiveRecord::Base.connection.foreign_keys(:jrc_operations_links).map(&:name)).to include('fk_project_links_r2_unit')
    later_keys.each do |key|
      restored = connection.foreign_keys(key.from_table).find { |candidate| candidate.name == key.name }
      expect(restored.to_table).to eq(key.to_table)
      expect(restored.options).to eq(key.options)
    end
  ensure
    AccountUser.reset_column_information
  end
end
