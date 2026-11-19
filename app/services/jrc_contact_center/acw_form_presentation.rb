# frozen_string_literal: true

class JrcContactCenter::AcwFormPresentation
  def self.summary(form)
    { id: form.id.to_s, name: form['form_name'], description: form['form_description'], status: form['form_status'],
      revision: form['form_revision'], updated_at: form['form_updated_at'], local_only: true, provider_applied: false }
  end

  def self.version(form, row, include_definition: true)
    item = row.as_json(only: %w[revision name description status created_at integrity_sha256])
    item.merge!('id' => form.id.to_s, 'version_id' => row.id.to_s, 'local_only' => true, 'provider_applied' => false,
                'actor_user_id' => row.actor_user_id.to_s, 'actor_account_user_id' => row.actor_account_user_id.to_s)
    item['definition'] = row.definition if include_definition
    item
  end
end
