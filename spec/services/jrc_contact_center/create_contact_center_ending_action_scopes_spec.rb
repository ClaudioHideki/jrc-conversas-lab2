require 'rails_helper'
require Rails.root.join('db/migrate/20261123034500_create_contact_center_ending_action_scopes')

RSpec.describe CreateContactCenterEndingActionScopes do
  include_context 'with a frozen ending reason catalogue'

  def remove_ending_action_scope_schema
    receipt = JrcContactCenter::EndingActionScopeSchemaReceipt
    receipt::RELATIONS.each do |table|
      receipt::TRIGGERS.each { |name| ApplicationRecord.connection.execute("DROP TRIGGER IF EXISTS #{name} ON #{table}") }
    end
    ApplicationRecord.connection.execute("DROP TABLE #{receipt::TABLE}")
    ApplicationRecord.connection.execute("DROP TABLE #{receipt::ACCOUNT_TABLE}")
    receipt::FUNCTIONS.each do |name|
      rows = ApplicationRecord.connection.select_values("SELECT oid::regprocedure::text FROM pg_proc WHERE proname='#{name}' " \
                                                        "AND pronamespace='public'::regnamespace")
      rows.each { |signature| ApplicationRecord.connection.execute("DROP FUNCTION #{signature}") }
    end
  end

  it 'anchors existing queues at installation time without rewriting populated native calls or catalogues' do
    previous = [record.attributes.deep_dup, session.reload.attributes.deep_dup, queue.attributes.deep_dup, unit.attributes.deep_dup]
    ApplicationRecord.transaction(requires_new: true) do
      remove_ending_action_scope_schema
      described_class.new.up
      captured = JrcContactCenter::EndingActionQueueScope.find_by!(account: account, source_queue_id: queue.id)
      expect(captured.created_at).to be > session.started_at
      expect(captured.revision).to eq(1)
      expect([record.reload.attributes, session.reload.attributes, queue.reload.attributes, unit.reload.attributes]).to eq(previous)
      expect(account.reload.settings.fetch('jrc_contact_center_acw')).not_to have_key('voice_ending_automations')
    end
  end

  it 'preserves populated scope history on exact migration reexecution' do
    queue
    original = JrcContactCenter::EndingActionQueueScope.where(account: account).map(&:attributes)
    expect { described_class.new.up }.not_to change(JrcContactCenter::EndingActionQueueScope, :count)
    expect(JrcContactCenter::EndingActionQueueScope.where(account: account).map(&:attributes)).to eq(original)
  end

  it 'rejects an incomplete existing schema instead of stamping missing guards as valid' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute('DROP TRIGGER cc_ending_action_queue_scope_changed ON jrc_contact_center_queues')
        described_class.new.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unexpected ending action scope schema/)
  end

  it 'preserves the immutable catalogue and confirmation receipts after adding its separately named scope guards' do
    require Rails.root.join('db/migrate/20261120023000_create_contact_center_ending_reason_versions')
    require Rails.root.join('db/migrate/20261122212900_create_contact_center_ending_reason_confirmations')
    record
    expect { CreateContactCenterEndingReasonVersions.new.up }.not_to change(JrcContactCenter::EndingReasonVersion, :count)
    expect { CreateContactCenterEndingReasonConfirmations.new.up }.not_to change(JrcContactCenter::EndingReasonConfirmation, :count)
  end

  it 'adds only the owned forward ledger and does not alter the native account retirement block' do
    original = record.attributes.deep_dup
    expect do
      Account.transaction(requires_new: true) { account.destroy! }
    end.to raise_error(ActiveRecord::InvalidForeignKey, /jrc_contact_center_/)
    expect(Account.exists?(account.id)).to be(true)
    expect(record.reload.attributes).to eq(original)
    expect(JrcContactCenter::EndingActionQueueScope.where(account: account, source_queue_id: queue.id)).to exist
  end
end
