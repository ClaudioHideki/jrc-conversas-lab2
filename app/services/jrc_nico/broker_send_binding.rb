class JrcNico::BrokerSendBinding
  UNAVAILABLE = 'O vínculo Flow/controle desta caixa mudou ou está indisponível. Prepare uma nova prévia coordenada.'.freeze
  QR_FIELDS = %w[id account_id inbox_id integration_id instance_id].freeze
  NATIVE_FIELDS = %w[id account_id inbox_id registration_id integration_id channel_id transport provider registration_revision].freeze
  REGISTRATION_FIELDS = %w[id account_id broker_origin host_origin organization_id credential_id credential_revision destination_revision
                           account_credential_version revision broker_registration_id broker_registration_revision state
                           expires_at credential_expires_at revoked_at tuple].freeze

  def self.resolve(account_id:, inbox_id:, lock: nil)
    ActiveRecord::Base.uncached do
      qr_scope = JrcBrokerInboxBinding.where(account_id: account_id, inbox_id: inbox_id)
      qr_scope = qr_scope.lock(lock) if lock
      qr = qr_scope.first
      native, registration = native_records(account_id, inbox_id, lock)
      return unless qr || native

      new(account_id, inbox_id, qr, native, registration).tap(&:validate!)
    end
  end

  def self.native_records(account_id, inbox_id, lock)
    scope = JrcFlowNativeBinding.where(account_id: account_id, inbox_id: inbox_id)
    native = scope.joins(:registration).where(jrc_flow_native_registrations: { state: 'ACTIVE' }).order(:id).first
    unless native
      raise ArgumentError, UNAVAILABLE if scope.exists?

      return [nil, nil]
    end
    native = scope.lock(lock).find(native.id) if lock
    registrations = JrcFlowNativeRegistration.where(id: native.registration_id)
    registrations = registrations.lock(lock) if lock
    [native, registrations.first!]
  end
  private_class_method :native_records

  def initialize(account_id, inbox_id, qr_binding, native, registration)
    @account_id = account_id
    @inbox_id = inbox_id
    @qr = qr_binding
    @native = native
    @registration = registration
  end

  def integration_id
    (@native || @qr).integration_id
  end

  def identity
    { 'kind' => @native ? 'NATIVE' : 'QR', 'qr' => identity_attributes(@qr, QR_FIELDS),
      'native' => identity_attributes(@native, NATIVE_FIELDS),
      'registration' => identity_attributes(@registration, REGISTRATION_FIELDS)&.as_json }
  end

  def validate!
    inbox = Inbox.find(@inbox_id)
    raise ArgumentError, UNAVAILABLE unless inbox.account_id == @account_id
    raise ArgumentError, UNAVAILABLE if @qr && (inbox.channel_type != 'Channel::Api' || @qr.integration_id != integration_id)

    validate_native! if @native
    self
  end

  def validate_snapshot!(snapshot)
    return unless @native
    return if snapshot['channelId'] == @native.channel_id && snapshot['credentialRevision'] == @registration.account_credential_version

    raise ArgumentError, UNAVAILABLE
  end

  private

  def identity_attributes(record, fields)
    record&.attributes&.slice(*fields)
  end

  def validate_native!
    now = ApplicationRecord.connection.select_value('SELECT clock_timestamp()').to_time
    valid = current_native_registration?(now)
    raise ArgumentError, UNAVAILABLE unless valid && compatible_control? && registered_target?
  end

  def current_native_registration?(now)
    @registration.account_id == @account_id && @registration.state == 'ACTIVE' && @registration.revoked_at.nil? &&
      @registration.expires_at > now && @registration.credential_expires_at > now &&
      @native.registration_revision == @registration.revision
  end

  def compatible_control?
    control = JrcBrokerIntegration.find_by(account_id: @account_id)
    control && control.broker_origin == @registration.broker_origin && control.organization_id == @registration.organization_id &&
      control.destination_revision == @registration.destination_revision &&
      @registration.host_origin == ENV.fetch('FRONTEND_URL', '').delete_suffix('/')
  end

  def registered_target?
    tuple = @registration.tuple
    expected = { 'accountId' => @account_id, 'credentialId' => @registration.credential_id,
                 'credentialRevision' => @registration.credential_revision, 'destinationRevision' => @registration.destination_revision,
                 'accountCredentialVersion' => @registration.account_credential_version }
    target = { 'inboxId' => @inbox_id, 'integrationId' => @native.integration_id, 'channelId' => @native.channel_id,
               'transport' => @native.transport, 'provider' => @native.provider }
    tuple.is_a?(Hash) && expected.all? { |key, value| tuple[key] == value } &&
      tuple['targets'].is_a?(Array) && tuple['targets'].count { |item| item == target } == 1
  end
end
