require 'rails_helper'
require Rails.root.join('db/migrate/20261119203000_create_contact_center_qualification_forms')

RSpec.describe CreateContactCenterQualificationForms do
  before do
    config = ActiveRecord::Base.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' &&
            %w[jrc_sd_bc_portal_concurrency_20261025_test jrc_cc_access_schema_reload_synthetic].include?(config.database)
    raise 'Private form schema mutation tests require the exclusively owned disposable database' unless owned
  end

  include_context 'with an owned immutable operational ACW form'

  it 'reexecutes as a verified no-op with actual synthetic answers and native attendance preserved' do
    manager.save_draft!(record, { reason_code: 'order', acw_form_answers: answers },
                        expected_revision: JrcContactCenter::QualificationDraftRevision.token(record))
    original = service.state.attributes
    described_class.new.up
    described_class.new.up
    expect(service.state.attributes).to eq(original)
    expect(record.reload.completed_at).to be_nil
    expect(JrcContactCenter::Qualification.where(account: account).count).to eq(1)
  end

  it 'does not accept a missing structural receipt as an already-upgraded schema' do
    connection = ActiveRecord::Base.connection
    original = connection.table_comment(described_class::TABLE)
    connection.transaction(requires_new: true) do
      connection.change_table_comment(described_class::TABLE, nil)
      expect { described_class.new.up }.to raise_error(ActiveRecord::MigrationError, /Unexpected private qualification form schema/)
      raise ActiveRecord::Rollback
    end
    expect(connection.table_comment(described_class::TABLE)).to eq(original)
  end

  it 'detects a missing child trigger instead of recreating it silently during reexecution' do
    connection = ActiveRecord::Base.connection
    connection.transaction(requires_new: true) do
      connection.execute('DROP TRIGGER jrc_cc_qualification_forms_immutable ON jrc_contact_center_qualification_forms')
      expect { described_class.new.up }.to raise_error(ActiveRecord::MigrationError, /Unexpected private qualification form schema/)
      raise ActiveRecord::Rollback
    end
    expect { described_class.new.up }.not_to raise_error
  end

  it 'includes the owned native-parent guard in the receipt and rejects its absence' do
    connection = ActiveRecord::Base.connection
    connection.transaction(requires_new: true) do
      connection.execute('DROP TRIGGER jrc_cc_qualification_forms_source ON jrc_contact_center_qualifications')
      expect { described_class.new.up }.to raise_error(ActiveRecord::MigrationError, /Unexpected private qualification form schema/)
      raise ActiveRecord::Rollback
    end
    expect { described_class.new.up }.not_to raise_error
  end

  it 'does not discard private evidence through an automatic down migration' do
    state = service.state
    expect { described_class.new.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    expect(JrcContactCenter::QualificationForm.exists?(state.id)).to be(true)
  end
end
