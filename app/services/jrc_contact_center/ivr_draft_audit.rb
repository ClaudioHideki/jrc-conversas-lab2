# frozen_string_literal: true

class JrcContactCenter::IvrDraftAudit
  def self.write!(draft, version, context, audio_proofs: [], calendar_proofs: [])
    attributes = version.slice('revision', 'status', 'integrity_sha256')
    changes = {
      'attributes' => [nil, attributes], 'cc_scope' => { 'before' => nil, 'after' => draft.scope_snapshot },
      'omitted_fields' => %w[name definition], 'schema_version' => 1
    }
    changes['validated_audio_versions'] = audio_proofs if audio_proofs.present?
    changes['validated_calendar_references'] = calendar_proofs if calendar_proofs.present?
    Audited.audit_class.create!(
      auditable: version, associated: context.fetch(:account), user: context.fetch(:user), action: 'create',
      comment: JrcContactCenter::ConfigurationAudit::COMMENT, audited_changes: changes
    )
  end
end
