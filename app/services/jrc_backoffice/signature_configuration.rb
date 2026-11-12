class JrcBackoffice::SignatureConfiguration
  class Changed < StandardError; end
  FIELDS = %w[environment integration_key impersonated_user_id external_account_id enabled].freeze

  def self.can_manage?(account:, actor:)
    return false unless actor.is_a?(User)

    account.reload
    actor.reload
    member = account.account_users.includes(:user).find_by(user_id: actor.id)
    return false unless account.active? && account.feature_enabled?('jrc_crm') && authorized_member?(member)

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
      credentials = JrcBackoffice::Signatures::Gateway.prepare_credentials(
        provider: record.provider, stored: record.persisted? ? record.credentials : {}, attributes: attributes
      )
      record.assign_attributes(attributes.slice(*FIELDS))
      record.revision += 1 if record.persisted?
      record.credentials = credentials
      record.save!
      JrcBackoffice::SignatureConnection.capture!(record, actor: @actor)
      audit!(record, 'signature_configuration_updated')
      record
    end
  end

  def check!(expected_revision:)
    authorize!
    record = current || raise(ActiveRecord::RecordNotFound)
    verify_revision!(record, expected_revision)
    revision = record.revision
    connection = record.connection
    JrcBackoffice::Signatures::Gateway.new(connection: connection).authenticate!
    record.with_lock do
      authorize!
      raise Changed, 'CONFIGURATION_CHANGED' unless record.revision == revision

      record.update!(authorization_checked_at: Time.current)
      connection.update!(authorization_checked_at: record.authorization_checked_at)
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

  def audit!(record, event)
    JrcCrm::AuditEvent.create!(account: @account, actor_type: 'User', actor_id: @actor.id, resource_type: record.class.name, resource_id: record.id,
                               event_type: event, metadata: { provider: 'docusign', revision: record.revision, environment: record.environment })
  end
end
