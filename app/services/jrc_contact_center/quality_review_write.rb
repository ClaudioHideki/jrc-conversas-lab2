# frozen_string_literal: true

require 'digest'
require 'json'

# The native Account mutex and current authority come from QualityReviewSource.
# Replaying a request cannot change its actor, source, input or existing immutable revision.
class JrcContactCenter::QualityReviewWrite
  def initialize(account:, member:)
    @account = account
    @member = member
  end

  def call(record_id, values)
    input = JrcContactCenter::QualityReviewInput.new(values)
    source = JrcContactCenter::QualityReviewSource.new(account: @account, member: @member, action: :quality_review)
    source.call(record_id) do |record, call, snapshot|
      raise JrcContactCenter::OperationError, 'quality_review_scope_unavailable' unless call.current_unit_id

      input.validate_source!(actual_sha256: snapshot.sha256, available_recommendation_ids: snapshot.recommendations.pluck('id'))
      persist(record, call, snapshot, input.attributes)
    end
  end

  private

  def revisions
    JrcContactCenter::QualityReviewRevision.where(account: @account)
  end

  def persist(record, call, snapshot, values)
    key = values.fetch('request_id')
    digest = Digest::SHA256.hexdigest(JSON.generate(values.sort.to_h))
    existing = revisions.find_by(request_key: key)
    return repeated!(existing, record, digest) if existing

    current = revisions.where(recording: record).maximum(:revision) || 0
    unless current == values.fetch('expected_revision')
      raise JrcContactCenter::OperationError.new('quality_review_revision_changed', status: :conflict)
    end

    row = revisions.create!(revision_values(record, call, snapshot, values).merge(revision: current + 1, input_sha256: digest))
    write_audit!(row)
    row
  end

  def repeated!(existing, record, digest)
    context = { account: @account, account_user: @member, user: @member.user }
    visible = JrcContactCenter::QualityReviewScope.new(context: context, relation: revisions.where(id: existing.id)).call.exists?
    raise ActiveRecord::RecordNotFound unless visible

    valid = existing.recording_id == record.id && existing.actor_account_user_id == @member.id && existing.actor_user_id == @member.user_id
    valid &&= ActiveSupport::SecurityUtils.secure_compare(existing.input_sha256, digest)
    raise JrcContactCenter::OperationError.new('quality_review_request_conflict', status: :conflict) unless valid

    existing
  end

  def revision_values(record, call, snapshot, values)
    {
      recording: record, call_session: call, actor_account_user_id: @member.id, actor_user_id: @member.user_id,
      request_key: values.fetch('request_id'), source_sha256: snapshot.sha256,
      original_analysis: JrcContactCenter::QualityReviewPresentation.original(snapshot),
      scope_snapshot: scope_for(call), reviewed_values: values.except('request_id', 'expected_revision', 'expected_source_sha256'),
      created_at: Time.current
    }
  end

  def scope_for(call)
    target = call.current_queue || call.current_unit
    return { 'account_id' => @account.id.to_s } unless target

    JrcContactCenter::ConfigurationAuditSnapshot.capture(target).fetch('scope')
  end

  def write_audit!(row)
    scope = row.scope_snapshot
    Audited.audit_class.create!(
      auditable: row, associated: @account, user: @member.user, action: 'create',
      comment: JrcContactCenter::ConfigurationAudit::COMMENT, audited_changes: {
        'schema_version' => 1, 'operation' => 'quality_review', 'revision' => row.revision,
        'recording_id' => row.recording_id.to_s, 'cc_scope' => { 'before' => scope, 'after' => scope }
      }
    )
  end
end
