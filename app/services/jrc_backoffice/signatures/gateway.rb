# A small boundary for the one installed connector. It grants no domain access:
# callers still authorize the exact account, contract version and operation.
class JrcBackoffice::Signatures::Gateway
  def initialize(connection:)
    @connection = connection.reload
    @adapter = self.class.adapter_class(@connection.provider).new(connection: @connection)
  end

  def self.adapter_class(provider)
    raise JrcBackoffice::Signatures::ProviderError.new(code: 'PROVIDER_UNAVAILABLE') unless provider == 'docusign'

    JrcBackoffice::Docusign::Adapter
  end

  def self.prepare_credentials(provider:, stored:, attributes:)
    adapter_class(provider).prepare_credentials(stored: stored, attributes: attributes)
  end

  delegate :capabilities, :callback_path, to: :@adapter

  %i[authenticate! status recipients resend remind cancel document recover_send notification].each do |operation|
    define_method(operation) do |*arguments, **keywords|
      ensure_account!
      @adapter.public_send(operation, *arguments, **keywords)
    end
  end

  def send_for_signature(document:, signers:, subject:, transaction_id:)
    ensure_account!
    raise JrcBackoffice::Signatures::ProviderError.new(code: 'CONNECTION_NOT_READY') unless @connection.delivery_ready?

    @adapter.send_for_signature(document: document, signers: signers, subject: subject, transaction_id: transaction_id)
  end

  private

  def ensure_account!
    account = @connection.account.reload
    return if account.active? && account.feature_enabled?('jrc_crm')

    raise JrcBackoffice::Signatures::ProviderError.new(code: 'CONNECTION_NOT_READY')
  end
end
