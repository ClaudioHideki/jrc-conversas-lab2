require 'rails_helper'
require Rails.root.join('db/migrate/20261121090000_create_contact_center_team_supervisions')

RSpec.describe CreateContactCenterTeamSupervisions do
  before do
    config = ActiveRecord::Base.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' &&
            %w[jrc_sd_bc_portal_concurrency_20261025_test jrc_cc_access_schema_reload_synthetic].include?(config.database)
    raise 'Team supervision migration requires the exclusively owned disposable database' unless owned
  end

  def in_owned_preupgrade_schema
    connection = ActiveRecord::Base.connection
    connection.transaction(requires_new: true) do
      connection.execute('CREATE SCHEMA cc_team_supervision_upgrade_synthetic')
      %w[accounts teams account_users jrc_contact_center_access_grants].each do |table|
        connection.execute("CREATE TABLE cc_team_supervision_upgrade_synthetic.#{table} (LIKE public.#{table} INCLUDING ALL)")
      end
      previous = connection.schema_search_path
      begin
        connection.schema_search_path = 'cc_team_supervision_upgrade_synthetic'
        yield connection
      ensure
        connection.schema_search_path = previous
      end
      raise ActiveRecord::Rollback
    end
  end

  it 'upgrades a populated native schema without adding memberships, permissions or supervision assignments' do
    account = create(:account)
    user = create(:user, :contact_center_eligible, account: account)
    member = account.account_users.find_by!(user: user)
    team = create(:team, account: account)
    counts = [TeamMember.count, JrcContactCenter::QueueMembership.count, JrcContactCenter::AccessGrant.count]
    in_owned_preupgrade_schema do |connection|
      rows = { 'accounts' => account.id, 'teams' => team.id, 'account_users' => member.id }
      rows.each { |table, id| connection.execute("INSERT INTO #{table} SELECT * FROM public.#{table} WHERE id = #{id}") }
      sql = "INSERT INTO jrc_contact_center_access_grants SELECT * FROM public.jrc_contact_center_access_grants " \
            "WHERE account_id = #{account.id}"
      connection.execute(sql)
      before = connection.select_all('SELECT * FROM jrc_contact_center_access_grants ORDER BY id').to_a
      described_class.new.up
      described_class.new.up
      expect(connection.select_value('SELECT COUNT(*) FROM jrc_contact_center_team_supervisions').to_i).to eq(0)
      expect(connection.select_all('SELECT * FROM jrc_contact_center_access_grants ORDER BY id').to_a).to eq(before)
    end
    expect([TeamMember.count, JrcContactCenter::QueueMembership.count, JrcContactCenter::AccessGrant.count]).to eq(counts)
  end

  it 'verifies the native fresh or reloaded schema idempotently without changing stored assignments' do
    count = JrcContactCenter::TeamSupervision.count
    connection = ActiveRecord::Base.connection
    timeout = connection.select_value('SHOW lock_timeout')
    described_class.new.up
    described_class.new.up
    expect(JrcContactCenter::TeamSupervision.count).to eq(count)
    expect(connection.foreign_keys(:jrc_contact_center_team_supervisions).length).to eq(3)
    expect(connection.indexes(:jrc_contact_center_team_supervisions).length).to eq(5)
    expect(connection.select_value('SHOW lock_timeout')).to eq(timeout)
  end

  %w[teams account_users].each do |table|
    it "rejects an existing schema missing the composite #{table} account boundary" do
      in_owned_preupgrade_schema do |connection|
        described_class.new.up
        key = connection.foreign_keys(:jrc_contact_center_team_supervisions).find { |row| row.to_table == table }
        connection.remove_foreign_key(:jrc_contact_center_team_supervisions, name: key.name)
        expect { described_class.new.up }.to raise_error(ActiveRecord::MigrationError, /Unexpected Call Center team supervision schema/)
      end
    end
  end

  it 'rejects a removed unique primary index instead of allowing competing principal supervisors' do
    in_owned_preupgrade_schema do |connection|
      described_class.new.up
      connection.remove_index(:jrc_contact_center_team_supervisions, name: described_class::PRIMARY_INDEX)
      expect { described_class.new.up }.to raise_error(ActiveRecord::MigrationError, /Unexpected Call Center team supervision schema/)
    end
  end

  it 'rejects a weakened same-named role constraint and restores the previous lock timeout after refusal' do
    in_owned_preupgrade_schema do |connection|
      described_class.new.up
      connection.remove_check_constraint(:jrc_contact_center_team_supervisions, name: described_class::KIND_CHECK)
      connection.add_check_constraint(:jrc_contact_center_team_supervisions, 'length(kind) > 0', name: described_class::KIND_CHECK)
      before = connection.select_value('SHOW lock_timeout')
      expect { described_class.new.up }.to raise_error(ActiveRecord::MigrationError, /Unexpected Call Center team supervision schema/)
      expect(connection.select_value('SHOW lock_timeout')).to eq(before)
    end
  end

  it 'rejects additional fields rather than silently accepting another implementation of the table' do
    in_owned_preupgrade_schema do |connection|
      described_class.new.up
      connection.add_column(:jrc_contact_center_team_supervisions, :permissions, :text)
      expect { described_class.new.up }.to raise_error(ActiveRecord::MigrationError, /Unexpected Call Center team supervision schema/)
    end
  end

  it 'rejects an unvalidated same-expression constraint instead of assuming existing records are verified' do
    in_owned_preupgrade_schema do |connection|
      described_class.new.up
      connection.remove_check_constraint(:jrc_contact_center_team_supervisions, name: described_class::KIND_CHECK)
      connection.add_check_constraint(:jrc_contact_center_team_supervisions, "kind IN ('primary', 'additional')",
                                     name: described_class::KIND_CHECK, validate: false)
      expect { described_class.new.up }.to raise_error(ActiveRecord::MigrationError, /Unexpected Call Center team supervision schema/)
    end
  end

  it 'rejects a default supervisor role instead of silently assigning imported records' do
    in_owned_preupgrade_schema do |connection|
      described_class.new.up
      connection.change_column_default(:jrc_contact_center_team_supervisions, :kind, 'additional')
      expect { described_class.new.up }.to raise_error(ActiveRecord::MigrationError, /Unexpected Call Center team supervision schema/)
    end
  end

  it 'rejects a nullable member identity instead of allowing anonymous operational responsibility' do
    in_owned_preupgrade_schema do |connection|
      described_class.new.up
      connection.change_column_null(:jrc_contact_center_team_supervisions, :account_user_id, true)
      expect { described_class.new.up }.to raise_error(ActiveRecord::MigrationError, /Unexpected Call Center team supervision schema/)
    end
  end

  it 'requires explicit rollback review rather than erasing operational metadata or its history' do
    expect { described_class.new.down }.to raise_error(ActiveRecord::IrreversibleMigration, /supervision and audit history/)
  end
end
