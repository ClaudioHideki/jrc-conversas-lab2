# frozen_string_literal: true

class JrcContactCenter::IvrDraftPresentation
  def self.summary(draft)
    { id: draft.id.to_s, unit_id: draft.unit_id.to_s, name: draft['draft_name'], status: draft['draft_status'],
      revision: draft['draft_revision'], updated_at: draft['draft_updated_at'], local_only: true, provider_applied: false }
  end

  def self.version(draft, row, include_definition: true)
    item = row.as_json(only: %w[revision name status created_at integrity_sha256])
    item.merge!('id' => draft.id.to_s, 'unit_id' => draft.unit_id.to_s, 'local_only' => true, 'provider_applied' => false,
                'actor_user_id' => row.actor_user_id.to_s, 'actor_account_user_id' => row.actor_account_user_id.to_s)
    item['definition'] = row.definition if include_definition
    item
  end
end
