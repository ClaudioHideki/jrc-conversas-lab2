require 'rails_helper'
require Rails.root.join('db/migrate/20261123063000_create_contact_center_ending_action_versions')

# Prepared, not executed. Every destructive schema statement below is limited to a rolled-back synthetic test transaction.
RSpec.describe CreateContactCenterEndingActionVersions do
  include_context 'with native private ending action definitions'

  def remove_owned_ending_version_schema
    receipt = JrcContactCenter::EndingActionVersionSchemaReceipt
    ApplicationRecord.connection.execute("DROP TABLE #{receipt::TABLE}")
    receipt::FUNCTIONS.each do |name|
      signatures = ApplicationRecord.connection.select_values("SELECT oid::regprocedure::text FROM pg_proc WHERE proname='#{name}' " \
                                                              "AND pronamespace='public'::regnamespace")
      signatures.each { |signature| ApplicationRecord.connection.execute("DROP FUNCTION #{signature}") }
    end
  end

  it 'installs only an empty forward history without creating a head, grant or operational record' do
    previous = account.reload.attributes.deep_dup
    ApplicationRecord.transaction(requires_new: true) do
      remove_owned_ending_version_schema
      described_class.new.up
      expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
      expect(account.reload.attributes).to eq(previous)
      expect(catalogue.head).to be_nil
      expect { JrcContactCenter::EndingActionVersionSchemaReceipt.new(ApplicationRecord.connection).verify! }.not_to raise_error
      raise ActiveRecord::Rollback
    end
  end

  it 'preserves populated definitions, native audit and account settings on exact reexecution' do
    version = record_private_ending_definition
    previous = [version.attributes.deep_dup, account.reload.settings.deep_dup, Audited.audit_class.where(associated: account).count]
    described_class.new.up
    expect([version.reload.attributes, account.reload.settings, Audited.audit_class.where(associated: account).count]).to eq(previous)
    expect(versions.count).to eq(1)
  end

  it 'rejects a partial schema instead of stamping a missing immutable trigger as valid' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute('DROP TRIGGER cc_ending_action_version_immutable ON jrc_contact_center_ending_action_versions')
        described_class.new.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unexpected ending action version schema/)
  end

  it 'rejects an unproven pre-existing head instead of inventing private definitions, actors or historical dates' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        remove_owned_ending_version_schema
        account.update!(settings: { JrcContactCenter::AcwPolicy::KEY => { catalogue.class::KEY => false } })
        described_class.new.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unproven ending action configuration/)
    account.reload
    expect(catalogue.head).to be_nil
    expect(versions).to be_empty
  end

  it 'leaves the existing confirmation and queue scope receipts valid after adding its separately named private guards' do
    require Rails.root.join('lib/jrc_contact_center/ending_confirmation_schema_receipt')
    require Rails.root.join('lib/jrc_contact_center/ending_action_scope_schema_receipt')
    connection = ApplicationRecord.connection
    expect { JrcContactCenter::EndingConfirmationSchemaReceipt.new(connection).verify! }.not_to raise_error
    expect { JrcContactCenter::EndingActionScopeSchemaReceipt.new(connection).verify! }.not_to raise_error
  end
end
