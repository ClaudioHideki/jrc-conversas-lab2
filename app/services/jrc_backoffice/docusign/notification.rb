# Translates an authenticated, encrypted Connect receipt. Provider fields and
# event names stay inside this connector, never in the operational workflow.
class JrcBackoffice::Docusign::Notification
  STATES = { 'envelope-completed' => 'completion_reported', 'envelope-declined' => 'declined', 'envelope-voided' => 'canceled' }.freeze

  def self.call(connection:, receipt:)
    data = receipt.payload
    valid = same_connection?(connection, receipt) && same_payload?(data, connection, receipt)
    raise JrcBackoffice::Signatures::ProviderError.new(code: 'NOTIFICATION_ORIGIN_INVALID') unless valid

    { external_id: receipt.envelope_id, state: STATES[receipt.event_type], generated_at: receipt.provider_generated_at }
  rescue KeyError, ArgumentError, TypeError, ActiveRecord::Encryption::Errors::Decryption
    raise JrcBackoffice::Signatures::ProviderError.new(code: 'NOTIFICATION_ORIGIN_INVALID')
  end

  def self.same_connection?(connection, receipt)
    [receipt.connection_id, receipt.account_id, receipt.integration_revision] == [connection.id, connection.account_id, connection.revision]
  end

  def self.same_payload?(data, connection, receipt)
    actual = [data.fetch('event'), data.fetch('data').fetch('accountId').downcase, data.fetch('data').fetch('envelopeId').downcase,
              Time.iso8601(data.fetch('generatedDateTime'))]
    actual == [receipt.event_type, connection.external_account_id.downcase, receipt.envelope_id.downcase, receipt.provider_generated_at]
  end
  private_class_method :same_connection?, :same_payload?
end
