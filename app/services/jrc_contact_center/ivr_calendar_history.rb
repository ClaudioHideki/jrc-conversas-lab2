# frozen_string_literal: true

# A model row alone does not attest a catalog reference: require its native creation audit as well.
class JrcContactCenter::IvrCalendarHistory
  def initialize(draft:, account:, unit_id:)
    @draft = draft
    @account = account
    @unit_id = unit_id.to_s
  end

  def proof(reference)
    return unless @draft

    row = matching_version(reference)
    return unless row && attested?(row, reference)

    { 'calendar_id' => reference.fetch('calendar_id'), 'sha256' => reference.fetch('sha256'),
      'unit_revision' => reference.fetch('unit_revision'), 'unit_id' => @unit_id, 'source' => 'native_ivr_version',
      'ivr_draft_id' => @draft.id.to_s, 'version_id' => row.id.to_s, 'revision' => row.revision,
      'version_sha256' => row.integrity_sha256 }
  end

  private

  def matching_version(reference)
    @draft.versions.where(account: @account).where(<<~SQL.squish, reference.to_json).order(:revision).first
      definition ->> 'schema_version' = '3' AND EXISTS (
        SELECT 1 FROM jsonb_array_elements(definition -> 'nodes') AS node(value)
        WHERE node.value -> 'calendar_reference' = ?::jsonb)
    SQL
  end

  def attested?(row, reference)
    records = Audited.audit_class.where(auditable: row, associated: @account, action: 'create',
                                        comment: JrcContactCenter::ConfigurationAudit::COMMENT).limit(2).to_a
    raise JrcContactCenter::OperationError.new('ivr_calendar_attestation_conflict', status: :conflict) if records.length > 1
    return false if records.empty?

    audit = records.sole
    data = audit.audited_changes
    valid_actor = audit.user_id == row.actor_user_id && audit.user_type == User.polymorphic_name
    valid_source = data.dig('attributes', 1, 'integrity_sha256') == row.integrity_sha256 &&
                   data.dig('cc_scope', 'after') == @draft.scope_snapshot
    valid_actor && valid_source && reference_attested?(data['validated_calendar_references'], reference)
  end

  def reference_attested?(proofs, reference)
    return false unless proofs.is_a?(Array) && proofs.length <= 128 && proofs.all?(Hash)

    expected = reference.slice('calendar_id', 'sha256', 'unit_revision').merge('unit_id' => @unit_id)
    proofs.any? do |proof|
      proof.slice(*expected.keys) == expected && %w[native_unit_catalog native_ivr_version].include?(proof['source'])
    end
  end
end
