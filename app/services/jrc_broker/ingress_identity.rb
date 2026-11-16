class JrcBroker::IngressIdentity
  def self.lock!(scope, input)
    value = ['jrc-ingress', scope.account.id, scope.inbox.id, input.fetch('organization_id'),
             input.fetch('integration_id'), input.fetch('broker_message_id')].join(':')
    connection = ApplicationRecord.connection
    connection.execute("SELECT pg_advisory_xact_lock(hashtextextended(#{connection.quote(value)},0))")
  end

  def self.assert_no_unproven_message!(scope, input)
    metadata = "CASE json_typeof(content_attributes) WHEN 'string' THEN (content_attributes #>> '{}')::jsonb " \
               "WHEN 'object' THEN content_attributes::jsonb ELSE '{}'::jsonb END"
    existing = scope.account.messages.where(inbox_id: scope.inbox.id, private: false)
                    .exists?(["lower((#{metadata})->>'jrc_broker_message_id') = ?", input.fetch('broker_message_id').downcase])
    raise ArgumentError, 'JRC_INGRESS_LEGACY_UNPROVEN' if existing
  end
end
