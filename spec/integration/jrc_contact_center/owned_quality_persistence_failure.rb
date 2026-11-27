# frozen_string_literal: true

require Rails.root.join('spec/integration/jrc_contact_center/owned_quality_source')

# Test-only failure injection in the exact hosted Chrome database; never loaded by the product.
module JrcContactCenter::SyntheticQualityPersistenceFailure
  def self.call(action, account_id, recording_id)
    SyntheticRecordedCallMedia.validate_environment!
    raise ArgumentError unless %w[enable inspect disable].include?(action)

    account = Account.find(account_id)
    marker = SyntheticRecordedCallMedia.control!(account)
    raise 'Exact owned recording required' unless marker.fetch('record_ids').include?(recording_id)

    record = TelephonyCallRecord.where(account: account).find(recording_id)
    SyntheticRecordedCallQuality.analysis(account.id, record.external_unique_id)
    connection = ApplicationRecord.connection
    name = "cc_synth_review_#{Integer(account.id)}_#{Integer(record.id)}"
    mutate(connection, name, action, account)
    counts(account, record).merge(source_sha: ENV.fetch('GITHUB_SHA'), constraint_active: connection.check_constraint_exists?(:audits, name: name))
  end

  def self.mutate(connection, name, action, account)
    if action == 'enable'
      raise 'A new owned review flow is required' if JrcContactCenter::QualityReviewRevision.exists?(account: account)
      raise 'Unexpected existing constraint remains preserved' if connection.check_constraint_exists?(:audits, name: name)

      condition = "auditable_type <> 'JrcContactCenter::QualityReviewRevision' OR associated_id <> #{Integer(account.id)}"
      connection.add_check_constraint(:audits, condition, name: name)
    elsif action == 'disable'
      raise 'Owned rejection constraint missing' unless connection.check_constraint_exists?(:audits, name: name)

      connection.remove_check_constraint(:audits, name: name)
    end
  end

  def self.counts(account, record)
    { account_id: account.id.to_s, recording_id: record.id.to_s,
      revisions: JrcContactCenter::QualityReviewRevision.where(account: account, recording: record).count,
      audits: Audited.audit_class.where(auditable_type: 'JrcContactCenter::QualityReviewRevision',
                                        associated_type: 'Account', associated_id: account.id).count }
  end
end
