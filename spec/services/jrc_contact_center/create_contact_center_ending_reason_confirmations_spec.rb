require 'rails_helper'
require Rails.root.join('db/migrate/20261122212900_create_contact_center_ending_reason_confirmations')

RSpec.describe CreateContactCenterEndingReasonConfirmations do
  include_context 'with a frozen ending reason catalogue'

  def connection
    ApplicationRecord.connection
  end

  it 'creates an empty optional domain over populated native calls without rewriting qualification or catalogue history' do
    previous = [record.attributes.deep_dup, session.reload.attributes.deep_dup,
                JrcContactCenter::EndingReasonVersion.where(account: account).map(&:attributes)]
    ApplicationRecord.transaction(requires_new: true) do
      connection.execute('DROP TRIGGER cc_ending_confirmation_fixed_reason ON jrc_contact_center_qualifications')
      connection.execute('DROP TABLE jrc_contact_center_ending_reason_confirmations')
      connection.execute('DROP FUNCTION cc_ending_confirmation_guard()')
      connection.execute('DROP FUNCTION cc_ending_confirmation_qualification_guard()')
      described_class.new.up
      expect([record.reload.attributes, session.reload.attributes,
              JrcContactCenter::EndingReasonVersion.where(account: account).map(&:attributes)]).to eq(previous)
      expect(JrcContactCenter::EndingReasonConfirmation.count).to eq(0)
      expect { described_class.new.up }.not_to change(JrcContactCenter::Qualification, :count)
    end
  end

  it 'retains a populated confirmation unchanged on exact migration reexecution' do
    input = { attributes: { reason_code: entry.fetch('code') }, expected_revision: JrcContactCenter::QualificationDraftRevision.token(record),
              request_key: SecureRandom.uuid }
    JrcContactCenter::ConfirmEndingReason.new(account: account, member: member).call(record, **input)
    row = JrcContactCenter::EndingReasonConfirmation.find_by!(account: account)
    previous = row.attributes.deep_dup
    expect { described_class.new.up }.not_to change(JrcContactCenter::EndingReasonConfirmation, :count)
    expect(row.reload.attributes).to eq(previous)
    expect(record.reload.completed_at).to be_nil
  end

  it 'rejects an incomplete existing schema instead of stamping a missing reason-protection trigger as valid' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        connection.execute('DROP TRIGGER cc_ending_confirmation_fixed_reason ON jrc_contact_center_qualifications')
        described_class.new.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unexpected ending confirmation schema/)
    expect(record.reload.completed_at).to be_nil
  end

  it 'preserves the original catalogue receipt verification after adding the separate confirmation guards' do
    require Rails.root.join('db/migrate/20261120023000_create_contact_center_ending_reason_versions')
    record
    expect { CreateContactCenterEndingReasonVersions.new.up }.not_to change(JrcContactCenter::EndingReasonVersion, :count)
    expect(JrcContactCenter::EndingReasonConfirmation.count).to eq(0)
  end
end
