require 'rails_helper'
require Rails.root.join('db/migrate/20261120023000_create_contact_center_ending_reason_versions')

RSpec.describe CreateContactCenterEndingReasonVersions do
  include_context 'with a frozen ending reason catalogue'

  before do
    config = ActiveRecord::Base.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' &&
            %w[jrc_sd_bc_portal_concurrency_20261025_test jrc_cc_access_schema_reload_synthetic].include?(config.database)
    raise 'Ending reason migration tests require the exclusively owned disposable database' unless owned
  end

  # Clone native table structures inside a rollback-only schema; no source schema, runtime, or data is replaced.
  def in_owned_preupgrade_schema
    connection = ActiveRecord::Base.connection
    connection.transaction(requires_new: true) do
      prepare_owned_schema(connection)
      previous = connection.schema_search_path
      begin
        connection.schema_search_path = 'cc_ending_reason_upgrade_synthetic'
        yield connection
      ensure
        connection.schema_search_path = previous
      end
      raise ActiveRecord::Rollback
    end
  end

  def prepare_owned_schema(connection)
    tables = %w[accounts audits jrc_contact_center_call_sessions jrc_contact_center_call_legs jrc_contact_center_qualifications
                jrc_contact_center_agent_state_events jrc_contact_center_queues]
    connection.execute('CREATE SCHEMA cc_ending_reason_upgrade_synthetic')
    tables.each { |table| connection.execute("CREATE TABLE cc_ending_reason_upgrade_synthetic.#{table} (LIKE public.#{table} INCLUDING ALL)") }
    connection.execute('ALTER TABLE cc_ending_reason_upgrade_synthetic.jrc_contact_center_call_sessions ' \
                       'DROP COLUMN ending_reason_version_id, DROP COLUMN ending_reason_captured_started_at')
    connection.execute("INSERT INTO cc_ending_reason_upgrade_synthetic.accounts SELECT * FROM public.accounts WHERE id = #{account.id}")
    connection.execute("INSERT INTO cc_ending_reason_upgrade_synthetic.audits SELECT * FROM public.audits WHERE associated_type = 'Account' " \
                       "AND associated_id = #{account.id}")
  end

  it 'upgrades populated native account and audit structures without fabricating dates or actors' do
    version = JrcContactCenter::EndingReasonVersion.where(account: account).sole
    in_owned_preupgrade_schema do |connection|
      described_class.new.up
      preserved = connection.select_one('SELECT * FROM jrc_contact_center_ending_reason_versions')
      expect(preserved.fetch('source_audit_id').to_i).to eq(version.source_audit_id)
      expect(preserved.fetch('integrity_sha256')).to eq(version.integrity_sha256)
      expect(connection.select_value('SELECT COUNT(*) FROM jrc_contact_center_ending_reason_versions').to_i).to eq(1)
      described_class.new.up
      expect(connection.select_value('SELECT COUNT(*) FROM jrc_contact_center_ending_reason_versions').to_i).to eq(1)
    end
    expect(version.reload.definition.fetch('version')).to eq(1)
  end

  it 'blocks an upgrade when the actual catalogue has no native audit history instead of guessing provenance' do
    in_owned_preupgrade_schema do |connection|
      connection.execute('DELETE FROM audits')
      expect { described_class.new.up }.to raise_error(ActiveRecord::MigrationError, /Unproven ending reason history/)
    end
    expect(JrcContactCenter::EndingReasonVersion.where(account: account).count).to eq(1)
  end

  it 'does not retroactively pin existing native call rows during upgrade' do
    call = session.reload
    in_owned_preupgrade_schema do |connection|
      names = call.attributes.keys - %w[ending_reason_version_id ending_reason_captured_started_at]
      columns = names.map { |key| connection.quote_column_name(key) }.join(', ')
      connection.execute("INSERT INTO jrc_contact_center_call_sessions (#{columns}) SELECT #{columns} FROM public.jrc_contact_center_call_sessions " \
                         "WHERE id = #{call.id}")
      described_class.new.up
      expect(connection.select_value("SELECT ending_reason_version_id FROM jrc_contact_center_call_sessions WHERE id = #{call.id}")).to be_nil
      captured = connection.select_value("SELECT ending_reason_captured_started_at FROM jrc_contact_center_call_sessions WHERE id = #{call.id}")
      expect(captured).to be_nil
    end
    expect(call.reload.ending_reason_version_id).to be_present
  end

  %w[missing_entries string_version].each do |malformation|
    it "blocks a proven but malformed legacy catalogue #{malformation} instead of accepting a nullable CHECK result" do
      definition = JrcContactCenter::EndingReasonVersion.where(account: account).sole.definition.deep_dup
      if malformation == 'missing_entries'
        definition.delete('entries')
      else
        definition['version'] = '1'
      end
      in_owned_preupgrade_schema do |connection|
        value = connection.quote(definition.to_json)
        connection.execute("UPDATE accounts SET settings = jsonb_set(settings, '{jrc_contact_center_acw,voice_reason_catalog}', #{value}::jsonb)")
        connection.execute("UPDATE audits SET audited_changes = jsonb_set(audited_changes, '{attributes,1,voice_reason_catalog}', #{value}::jsonb) " \
                           "WHERE comment = 'jrc_contact_center_acw_policy_v1'")
        expect do
          connection.transaction(requires_new: true) { described_class.new.up }
        end.to raise_error(ActiveRecord::StatementInvalid, /cc_ending_reason_definition/)
      end
      expect(JrcContactCenter::EndingReasonVersion.where(account: account).sole.definition.fetch('entries')).to eq([entry])
    end
  end

  it 'verifies reexecution and refuses missing trigger evidence without rebuilding the guard silently' do
    original = JrcContactCenter::EndingReasonVersion.where(account: account).sole.attributes
    described_class.new.up
    connection = ActiveRecord::Base.connection
    connection.transaction(requires_new: true) do
      connection.execute('DROP TRIGGER cc_ending_reason_call_guard ON jrc_contact_center_call_sessions')
      expect { described_class.new.up }.to raise_error(ActiveRecord::MigrationError, /Unexpected ending reason ledger schema/)
      raise ActiveRecord::Rollback
    end
    expect(JrcContactCenter::EndingReasonVersion.where(account: account).sole.attributes).to eq(original)
    expect { described_class.new.up }.not_to raise_error
  end
end
