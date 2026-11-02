# Called only when admitting a new delivery. Once admitted, the delivery must
# retain this connection ID; queued work must not select the default again.
class JrcBackoffice::Signatures::ConnectionSelection
  def self.for_new_delivery(account:)
    current = account.reload
    raise JrcBackoffice::Signatures::ProviderError.new(code: 'CONNECTION_NOT_READY') unless current.active? && current.feature_enabled?('jrc_crm')

    integration = JrcBackoffice::SignatureIntegration.find_by(account_id: current.id)
    connection = integration&.connection
    unless connection&.current_for_new_delivery? && connection.delivery_ready?
      raise JrcBackoffice::Signatures::ProviderError.new(code: 'CONNECTION_NOT_READY')
    end

    JrcBackoffice::Signatures::Gateway.adapter_class(connection.provider)
    connection
  end
end
