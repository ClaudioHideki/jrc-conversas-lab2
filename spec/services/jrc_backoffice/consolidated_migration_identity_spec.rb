require 'rails_helper'
require Rails.root.join('db/migrate/20261102090100_create_backoffice_signature_deliveries')
require Rails.root.join('db/migrate/20261102100100_allow_signature_reconciliation_observations')

RSpec.describe 'Consolidated LAB2 migration identities' do
  let(:connection) { ActiveRecord::Base.connection }

  it 'refuses to recreate existing A-G signature history instead of guessing an adoption from a numeric version' do
    expect(connection.table_exists?(:jrc_backoffice_signature_deliveries)).to be(true)
    expect do
      CreateBackofficeSignatureDeliveries.new.up
    end.to raise_error(ActiveRecord::MigrationError, /Existing A-G signature history requires explicit admission/)
  end

  it 'refuses the legacy A-G origin without the actual LAB2 Broker migration' do
    connection.transaction(requires_new: true) do
      connection.rename_table(:jrc_broker_webhook_obligations, :synthetic_hidden_broker_obligations)
      expect do
        CreateBackofficeSignatureDeliveries.new.up
      end.to raise_error(ActiveRecord::MigrationError, /Consolidated LAB2 main history required/)
      raise ActiveRecord::Rollback
    end
    expect(connection.table_exists?(:jrc_broker_webhook_obligations)).to be(true)
  end

  it 'requires the actual human-assignment history before updating the signature reconciliation constraint' do
    connection.transaction(requires_new: true) do
      connection.rename_table(:jrc_human_assignment_policy_events, :synthetic_hidden_policy_events)
      expect do
        AllowSignatureReconciliationObservations.new.up
      end.to raise_error(ActiveRecord::MigrationError, /Consolidated LAB2 main history required/)
      raise ActiveRecord::Rollback
    end
    expect(connection.table_exists?(:jrc_human_assignment_policy_events)).to be(true)
  end
end
