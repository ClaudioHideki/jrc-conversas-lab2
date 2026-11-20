require 'rails_helper'
require Rails.root.join('db/migrate/20261120070000_create_contact_center_team_states')

RSpec.describe CreateContactCenterTeamStates do
  before do
    config = ActiveRecord::Base.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' &&
            %w[jrc_sd_bc_portal_concurrency_20261025_test jrc_cc_access_schema_reload_synthetic].include?(config.database)
    raise 'Team state migration requires the exclusively owned disposable database' unless owned
  end

  def in_owned_preupgrade_schema
    connection = ActiveRecord::Base.connection
    connection.transaction(requires_new: true) do
      connection.execute('CREATE SCHEMA cc_team_state_upgrade_synthetic')
      %w[accounts teams jrc_contact_center_access_grants].each do |table|
        connection.execute("CREATE TABLE cc_team_state_upgrade_synthetic.#{table} (LIKE public.#{table} INCLUDING ALL)")
      end
      previous = connection.schema_search_path
      begin
        connection.schema_search_path = 'cc_team_state_upgrade_synthetic'
        yield connection
      ensure
        connection.schema_search_path = previous
      end
      raise ActiveRecord::Rollback
    end
  end

  it 'creates the empty extension on an existing schema without granting eligibility or changing historical grant rows' do
    account = create(:account)
    team = create(:team, account: account)
    grant = JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: ['jrc_contact_center_monitor'])
    in_owned_preupgrade_schema do |connection|
      rows = { 'accounts' => account.id, 'teams' => team.id, 'jrc_contact_center_access_grants' => grant.id }
      rows.each do |table, id|
        connection.execute("INSERT INTO #{table} SELECT * FROM public.#{table} WHERE id = #{id}")
      end
      before = connection.select_one("SELECT * FROM jrc_contact_center_access_grants WHERE id = #{grant.id}")
      described_class.new.up
      expect(connection.select_value('SELECT COUNT(*) FROM jrc_contact_center_team_states').to_i).to eq(0)
      expect(connection.select_one("SELECT * FROM jrc_contact_center_access_grants WHERE id = #{grant.id}")).to eq(before)
      described_class.new.up
      expect(connection.select_value('SELECT COUNT(*) FROM jrc_contact_center_team_states').to_i).to eq(0)
    end
    expect(grant.reload.allowed).to eq(['jrc_contact_center_monitor'])
  end

  it 'verifies the real migrated or reloaded schema idempotently without inserting status rows' do
    count = JrcContactCenter::TeamState.count
    described_class.new.up
    described_class.new.up
    expect(JrcContactCenter::TeamState.count).to eq(count)
    expect(ActiveRecord::Base.connection.foreign_keys(:jrc_contact_center_team_states).length).to eq(2)
  end

  it 'blocks a divergent table rather than accepting a removed foreign key' do
    in_owned_preupgrade_schema do |connection|
      described_class.new.up
      key = connection.foreign_keys(:jrc_contact_center_team_states).find { |row| row.to_table == 'teams' }
      connection.remove_foreign_key(:jrc_contact_center_team_states, name: key.name)
      expect { described_class.new.up }.to raise_error(ActiveRecord::MigrationError, /Unexpected Call Center team state schema/)
    end
  end

  it 'does not offer a rollback that silently restores suspended sources' do
    expect { described_class.new.down }.to raise_error(ActiveRecord::IrreversibleMigration, /reactivate suspended/)
  end
end
