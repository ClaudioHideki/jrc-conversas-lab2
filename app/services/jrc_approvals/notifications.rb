# Only bounded navigation data enters the native in-app feed. Never serialize an approval snapshot or audit data.
class JrcApprovals::Notifications
  TYPE = 'approval_event'.freeze
  REQUEST_EVENTS = %w[request_created request_revised decision_recorded request_adjusted request_cancel request_expire request_reopen].freeze
  DELEGATION_EVENTS = %w[delegation_granted delegation_revoked delegation_expired own_delegation_granted own_delegation_revoked
                         own_delegation_expired].freeze
  EVENTS = (REQUEST_EVENTS + DELEGATION_EVENTS).freeze
  ACTORS = ['JrcApprovals::Request', 'JrcApprovals::AuditEvent'].freeze

  def self.actor!(account:, user:, type:, id:)
    actor = case type
            when 'JrcApprovals::Request' then JrcApprovals::Request.where(account_id: account.id).find(id)
            when 'JrcApprovals::AuditEvent' then JrcApprovals::AuditEvent.where(account_id: account.id).find(id)
            else raise ActiveRecord::RecordNotFound
            end
    raise ActiveRecord::RecordNotFound unless actor_visible?(account: account, user: user, actor: actor)

    actor
  end

  def self.actor_visible?(account:, user:, actor:)
    account = Account.find(account.id)
    auth = JrcApprovals::Authorization.new(account: account, user: user)
    member = auth.member!
    raise Pundit::NotAuthorizedError unless actor.account_id == account.id

    if actor.is_a?(JrcApprovals::Request)
      JrcApprovals::RequestVisibility.authorize!(account: account, user: user, record: actor)
    else
      delegation_visible!(account, auth, member, actor)
    end
    true
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound, JrcApprovals::Error
    false
  end

  def self.visible?(notification)
    return false unless notification.notification_type == TYPE && ACTORS.include?(notification.primary_actor_type) &&
                        EVENTS.include?(notification.meta&.dig('approval_event'))

    actor!(account: notification.account, user: notification.user, type: notification.primary_actor_type, id: notification.primary_actor_id)
    true
  rescue ActiveRecord::RecordNotFound
    false
  end

  def self.restrict(relation)
    allowed = relation.where(notification_type: TYPE).filter_map { |notice| notice.id if visible?(notice) }
    relation.where.not(notification_type: TYPE).or(relation.where(id: allowed))
  end

  def self.payload(notification)
    return {} unless visible?(notification)

    attributes = notification.attributes.slice('id', 'notification_type', 'primary_actor_type', 'primary_actor_id', 'account_id',
                                               'read_at', 'snoozed_until')
    attributes.merge(
      'notification_type' => TYPE, 'created_at' => notification.created_at.to_i, 'last_activity_at' => notification.last_activity_at.to_i,
      'primary_actor' => { id: notification.primary_actor_id, account_id: notification.account_id, meta: {} },
      'user' => { id: notification.user_id }, 'secondary_actor' => nil,
      'meta' => { 'approval_event' => notification.meta.fetch('approval_event'),
                  'approval_target' => navigation_target(notification) },
      'push_message_title' => I18n.t('notifications.notification_title.approval_event'),
      'push_message_body' => I18n.t('notifications.approval_event_body')
    )
  end

  def self.navigation_target(notification)
    return 'inbox' if notification.primary_actor_type == 'JrcApprovals::Request'

    event = JrcApprovals::AuditEvent.where(account_id: notification.account_id).find(notification.primary_actor_id)
    event.event_type == JrcApprovals::OwnDelegations::EVENT ? 'own-delegations' : 'inbox'
  end
  private_class_method :navigation_target

  def self.delegation_visible!(account, auth, member, actor)
    case actor.event_type
    when JrcApprovals::OwnDelegations::EVENT
      grant = JrcApprovals::OwnDelegations.find!(account, actor.id)
      action = grant.principal_id == member.id ? 'delegate' : 'decide'
      raise Pundit::NotAuthorizedError unless [grant.principal_id, grant.delegate_id].include?(member.id)

      authorize_delegation_scope!(auth, action, grant.issuer_company_id, grant.business_unit_id)
    when 'delegation_granted'
      scoped_delegation_visible!(account, auth, member, actor)
    else
      raise Pundit::NotAuthorizedError
    end
  end

  def self.scoped_delegation_visible!(account, auth, member, actor)
    grant = JrcApprovals::Delegation.where(account_id: account.id).find(actor.data.fetch('delegation_id'))
    raise Pundit::NotAuthorizedError unless [grant.principal_id, grant.delegate_id].include?(member.id)

    company_id, unit_id = grant.policy_version.publication.values_at('issuer_company_id', 'business_unit_id')
    authorize_delegation_scope!(auth, 'decide', company_id, unit_id)
  end

  def self.authorize_delegation_scope!(auth, action, company_id, unit_id)
    auth.authorize!(action, company_id: company_id, unit_id: unit_id)
  rescue Pundit::NotAuthorizedError
    auth.authorize!('policy_manage', company_id: company_id, unit_id: unit_id)
  end
  private_class_method :delegation_visible!, :scoped_delegation_visible!, :authorize_delegation_scope!
end
