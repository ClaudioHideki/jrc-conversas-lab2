require 'base64'

# Provider-specific authentication, fields and reported states stay here.
# "Completion reported" must still pass version/recipient/PDF evidence checks.
class JrcBackoffice::Docusign::Adapter
  CAPABILITIES = %i[send status recipients resend remind cancel final_document certificate].freeze
  STATES = { 'created' => 'pending', 'sent' => 'waiting', 'delivered' => 'waiting', 'completed' => 'completion_reported',
             'declined' => 'declined', 'voided' => 'canceled' }.freeze

  def self.prepare_credentials(stored:, attributes:)
    JrcBackoffice::Docusign::Credentials.prepare(stored: stored, attributes: attributes)
  end

  def initialize(connection:)
    @connection = connection
    @client = JrcBackoffice::Docusign::Client.new(integration: connection)
  end

  def capabilities
    CAPABILITIES
  end

  def authenticate!
    @client.check_authorization!
  end

  def callback_path
    "/webhooks/docusign/#{@connection.public_id}"
  end

  def send_for_signature(document:, signers:, subject:, transaction_id:)
    unless document.is_a?(String) && document.start_with?('%PDF-') && document.bytesize <= 20.megabytes && signers.present?
      raise ArgumentError, 'A PDF up to 20 MiB and at least one signer are required'
    end

    definition = { 'emailSubject' => subject, 'documents' => [{ 'documentId' => '1', 'name' => 'Contrato.pdf', 'fileExtension' => 'pdf',
                                                                'documentBase64' => Base64.strict_encode64(document) }],
                   'recipients' => { 'signers' => signers.map { |signer| signer_definition(signer) } } }
    result = @client.create_envelope(definition: definition, transaction_id: transaction_id)
    { external_id: result.fetch('envelopeId'), state: 'sent', provider_state: result.fetch('status') }
  end

  def status(external_id)
    result = @client.envelope(external_id)
    raise JrcBackoffice::Signatures::ProviderError.new(code: 'PROVIDER_RESPONSE_INVALID') unless result['envelopeId'].to_s.casecmp?(external_id)

    { external_id: external_id, state: STATES.fetch(result['status'], 'unknown'), provider_state: result['status'] }
  end

  def recipients(external_id)
    rows = @client.recipients(external_id)
    { signers: Array(rows['signers']).map do |signer|
      { id: signer['recipientId'], name: signer['name'], email: signer['email'], completed: signer['status'] == 'completed',
        signed_at: signer['signedDateTime'], provider_state: signer['status'] }
    end }
  end

  def resend(external_id)
    @client.resend(external_id)
    true
  end

  # DocuSign uses the same resend operation for an immediate reminder.
  alias remind resend

  def cancel(external_id, reason:)
    @client.cancel(external_id, reason: reason)
    true
  end

  def document(external_id, kind:)
    raise ArgumentError, 'Unsupported signature document' unless %i[final_document certificate].include?(kind)

    @client.document(external_id, kind: kind == :final_document ? 'combined' : 'certificate')
  end

  private

  def signer_definition(signer)
    anchor = { 'anchorString' => signer.fetch(:anchor), 'anchorUnits' => 'pixels', 'anchorIgnoreIfNotPresent' => 'false' }
    { 'recipientId' => signer.fetch(:id).to_s, 'name' => signer.fetch(:name), 'email' => signer.fetch(:email), 'routingOrder' => '1',
      'tabs' => { 'signHereTabs' => [anchor] } }
  end
end
