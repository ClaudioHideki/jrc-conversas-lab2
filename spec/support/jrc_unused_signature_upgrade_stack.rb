require Rails.root.join('db/migrate/20261105120000_create_backoffice_signature_artifact_bundles')
require Rails.root.join('db/migrate/20261105121000_create_backoffice_signature_acceptances')

# Exercise older unused extensions below their newer, EMPTY dependents. All DDL
# is rolled back to the complete current schema, including irreversible forward
# guards. This is not a production downgrade or a history archival mechanism.
module JrcUnusedSignatureUpgradeStack
  def with_unused_signature_evidence
    connection = ActiveRecord::Base.connection
    owned = ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            ENV.fetch('JRC_AG_POSTGRES_SERVICE_ID', '').match?(/\A[a-f0-9]{12,64}\z/)
    raise 'Exclusive hosted synthetic upgrade service required' unless owned && ENV['JRC_AG_EXCLUSIVE_SPEC'].present?

    tables = %w[jrc_backoffice_signature_acceptances jrc_backoffice_signature_artifact_bundles]
    raise 'Existing signature evidence must remain intact' if tables.any? { |table| connection.select_value("SELECT count(*) FROM #{table}").to_i.positive? }

    original = tables.to_h { |table| [table, connection.foreign_keys(table).map(&:name).sort] }
    connection.transaction(requires_new: true) do
      CreateBackofficeSignatureAcceptances.new.migrate(:down)
      CreateBackofficeSignatureArtifactBundles.new.migrate(:down)
      yield
      raise ActiveRecord::Rollback
    end
    expect(tables.to_h { |table| [table, connection.foreign_keys(table).map(&:name).sort] }).to eq(original)
    expect(connection.select_value("SELECT count(*) FROM pg_trigger WHERE tgname='jrc_bo_signature_acceptance_pin'").to_i).to eq(1)
  ensure
    ActiveRecord::Base.connection.schema_cache.clear!
  end
end

RSpec.configure { |config| config.include JrcUnusedSignatureUpgradeStack, unused_signature_upgrade: true }
