class JrcBackoffice::SignatureConfiguration
  class Changed < StandardError; end
  FIELDS = %w[environment integration_key impersonated_user_id external_account_id enabled].freeze

  def self.can_manage?(account:, actor:)
    member = account.account_users.includes(:user).find_by(user_id: actor&.id)
    return false unless account.reload.active? && account.feature_enabled?('jrc_crm') && authorized_member?(member)

    coverage = JrcCrm::CorporateCoverage.new(account: account, user: member.user)
    !coverage.configured? || coverage.group?
  end

  def self.authorized_member?(member)
    member&.administrator? && member.user.active_for_authentication? && member.permissions.include?('jrc_crm')
  end
  private_class_method :authorized_member?

  def initialize(account:, actor:)
    @account = account
    @actor = actor
  end

  def current
    JrcBackoffice::SignatureIntegration.find_by(account_id: @account.id)
  end

  def save!(attributes:, expected_revision:)
    authorize!
    attributes = attributes.stringify_keys
    @account.with_lock do
      authorize!
      record = current || JrcBackoffice::SignatureIntegration.new(account: @account, created_by: @actor)
      verify_revision!(record, expected_revision)
      credentials = merge_credentials(record, attributes)
      validate_credentials!(credentials)
      record.assign_attributes(attributes.slice(*FIELDS))
      record.revision += 1 if record.persisted?
      record.credentials = credentials
      record.save!
      audit!(record, 'signature_configuration_updated')
      record
    end
  end

  def check!(expected_revision:)
    authorize!
    record = current || raise(ActiveRecord::RecordNotFound)
    verify_revision!(record, expected_revision)
    revision = record.revision
    JrcBackoffice::Docusign::Client.new(integration: record).check_authorization!
    record.with_lock do
      authorize!
      raise Changed, 'CONFIGURATION_CHANGED' unless record.revision == revision

      record.update!(authorization_checked_at: Time.current)
      audit!(record, 'signature_authorization_checked')
    end
    record
  end

  private

  def authorize!
    raise Pundit::NotAuthorizedError unless self.class.can_manage?(account: @account, actor: @actor)
  end

  def verify_revision!(record, expected)
    version = Integer(expected.to_s, 10)
    raise Changed, 'CONFIGURATION_CHANGED' unless version == (record.persisted? ? record.revision : 0)
  rescue ArgumentError
    raise Changed, 'CONFIGURATION_CHANGED'
  end

  def merge_credentials(record, attributes)
    data = record.persisted? ? record.credentials : {}
    key = attributes['private_key']
    if key.present?
      raise JrcBackoffice::Docusign::Error.new(code: 'CREDENTIAL_INVALID') unless key.is_a?(String) && key.bytesize <= 16.kilobytes

      data['private_key'] = key.strip
    end
    data['connect_hmac_keys'] = attributes['connect_hmac_keys'] if attributes['connect_hmac_keys'].present?
    data
  end

  def validate_credentials!(data)
    key = OpenSSL::PKey::RSA.new(data['private_key'].to_s)
    return if key.private? && key.n.num_bits >= 2048 && valid_hmac_keys?(data['connect_hmac_keys'])

    raise JrcBackoffice::Docusign::Error.new(code: 'CREDENTIAL_INVALID')
  rescue OpenSSL::PKey::PKeyError
    raise JrcBackoffice::Docusign::Error.new(code: 'CREDENTIAL_INVALID')
  end

  def valid_hmac_keys?(keys)
    keys.is_a?(Array) && keys.size.between?(1, 5) && keys.all? { |key| key.is_a?(String) && key.bytesize.between?(32, 256) }
  end

  def audit!(record, event)
    JrcCrm::AuditEvent.create!(account: @account, actor_type: 'User', actor_id: @actor.id, resource_type: record.class.name, resource_id: record.id,
                               event_type: event, metadata: { provider: 'docusign', revision: record.revision, environment: record.environment })
  end
end
