# frozen_string_literal: true

class JrcContactCenter::ConfigurationAudit
  COMMENT = 'jrc_contact_center_configuration_v1'
  ROLE_COMMENT = 'JRC Call Center native capabilities'
  AUTHORITY_COMMENT = 'jrc_contact_center_authority_v1'
  ACW_COMMENT = 'jrc_contact_center_acw_policy_v1'
  PAUSE_COMMENT = 'jrc_contact_center_pause_catalog_v1'
  COMMENTS = [COMMENT, ROLE_COMMENT, AUTHORITY_COMMENT, ACW_COMMENT, PAUSE_COMMENT].freeze

  def self.write!(record, action:, before:, after:)
    fields = JrcContactCenter::ConfigurationAuditSnapshot::FIELDS.fetch(record.class.name)
    changed = record.saved_changes.keys - %w[id account_id created_at updated_at]
    omitted = changed - fields
    return if action == 'update' && before == after && omitted.empty?

    Audited.audit_class.create!(
      auditable: record, associated: record.account, user: Current.user, action: action,
      comment: record.is_a?(JrcContactCenter::AccessGrant) ? AUTHORITY_COMMENT : COMMENT, audited_changes: {
        'attributes' => [before&.fetch('attributes'), after&.fetch('attributes')],
        'cc_scope' => { 'before' => before&.fetch('scope'), 'after' => after&.fetch('scope') },
        'omitted_fields' => omitted, 'schema_version' => 1
      }.merge(manager_review(record))
    )
  end

  def self.manager_review(record)
    return {} unless record.is_a?(JrcContactCenter::QueueMembership) && record.cc_withdrawal_review

    values = record.cc_withdrawal_review.slice(*JrcContactCenter::QueueWithdrawalReview::AUDIT_FIELDS).deep_dup
    record.cc_withdrawal_review = nil
    { 'manager_review' => values }
  end
  private_class_method :manager_review
end
