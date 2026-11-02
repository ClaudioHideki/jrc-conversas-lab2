require 'digest'

# Receipt is durable and tenant-bound. It is not evidence of a completed signature.
class JrcBackoffice::Docusign::ConnectInbox
  class Rejected < StandardError; end
  EVENTS = %w[envelope-sent envelope-delivered envelope-completed envelope-declined envelope-voided
              recipient-sent recipient-delivered recipient-completed recipient-declined].freeze

  def self.receive!(public_id:, raw_body:, signatures:)
    integration = JrcBackoffice::SignatureIntegration.find_by(public_id: public_id)
    raise Rejected unless integration

    integration.with_lock do
      account = integration.account.reload
      raise Rejected unless integration.enabled? && account.active? && account.feature_enabled?('jrc_crm')

      keys = integration.credentials['connect_hmac_keys']
      raise Rejected unless JrcBackoffice::Docusign::ConnectVerifier.valid?(raw_body: raw_body, signatures: signatures, keys: keys)

      data = JSON.parse(raw_body)
      validate!(data, integration)
      notification = persist!(integration, raw_body, data)
      confirm_connection!(integration)
      notification
    end
  rescue JSON::ParserError, ArgumentError, JrcBackoffice::Docusign::Error
    raise Rejected
  end

  def self.validate!(data, integration)
    validate_schema!(data)

    details = data['data']
    valid = details['accountId'].is_a?(String) && details['accountId'].casecmp?(integration.external_account_id) &&
            details['envelopeId'].is_a?(String) && details['envelopeId'].match?(JrcBackoffice::SignatureIntegration::UUID)
    raise Rejected unless valid && data['generatedDateTime'].is_a?(String)

    Time.iso8601(data['generatedDateTime'])
  end
  private_class_method :validate!

  def self.validate_schema!(data)
    raise Rejected unless data.is_a?(Hash) && EVENTS.include?(data['event']) && data['data'].is_a?(Hash)
  end
  private_class_method :validate_schema!

  def self.confirm_connection!(integration)
    return if integration.connect_checked_at

    integration.update!(connect_checked_at: Time.current)
    JrcCrm::AuditEvent.create!(account_id: integration.account_id, actor_type: 'Provider', event_type: 'signature_connect_checked',
                               resource_type: integration.class.name, resource_id: integration.id,
                               metadata: { provider: 'docusign', revision: integration.revision })
  end
  private_class_method :confirm_connection!

  def self.persist!(integration, raw_body, data)
    JrcBackoffice::SignatureNotification.find_or_create_by!(integration_id: integration.id, integration_revision: integration.revision,
                                                            body_sha256: Digest::SHA256.hexdigest(raw_body)) do |record|
      record.account_id = integration.account_id
      record.event_type = data['event']
      record.envelope_id = data['data']['envelopeId']
      record.provider_generated_at = Time.iso8601(data['generatedDateTime'])
      record.payload = data
    end
  end
  private_class_method :persist!
end
