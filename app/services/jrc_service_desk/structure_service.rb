# frozen_string_literal: true

# Explicit Account structural authority only. Never changes tickets or grants roles.
class JrcServiceDesk::StructureService
  Result = Struct.new(:record, :audit_id, keyword_init: true)

  def initialize(user_context:)
    @native_context = user_context
  end

  def create(resource:, attributes:, reason:, idempotency_key:)
    data = JrcServiceDesk::StructureContract.attributes(resource, attributes, create: true)
    mutate(resource, data, reason, idempotency_key, nil, nil)
  end

  def update(resource:, record_id:, attributes:, reason:, idempotency_key:, expected_revision:)
    data = JrcServiceDesk::StructureContract.attributes(resource, attributes, create: false)
    mutate(resource, data, reason, idempotency_key, JrcServiceDesk::Input.id(record_id),
      JrcServiceDesk::StructureContract.revision(expected_revision))
  end

  private

  def mutate(resource, data, reason, key, record_id, revision)
    klass = JrcServiceDesk::StructureRecords.model(resource)
    reason = JrcServiceDesk::StructureContract.reason(reason)
    key = JrcServiceDesk::Input.request_key(key)
    fingerprint = JrcServiceDesk::CanonicalJson.digest('resource' => resource, 'id' => record_id,
      'revision' => revision, 'fields' => data, 'reason' => reason)
    with_authority(resource) do
      audit = JrcServiceDesk::StructureAudit.new(account: @context.account, actor: @context.user, account_user: @context.account_user)
      prior = audit.prior(key)
      if prior
        info = audit.metadata(prior)
        raise JrcServiceDesk::IdempotencyConflict unless info['resource'] == resource && info['fingerprint'] == fingerprint
        record = klass.where(account_id: @context.account.id).find(info.fetch('record_id'))
        authorize!(record, :update?)
        next Result.new(record: record, audit_id: prior.id)
      end
      record = record_id ? klass.where(account_id: @context.account.id).lock.find(record_id) : klass.new(account: @context.account)
      authorize!(record, record_id ? :update? : :create?)
      if record_id && JrcServiceDesk::StructureRecords.revision(resource, record) != revision
        raise ActiveRecord::StaleObjectError.new(record, 'update')
      end
      before = record_id ? JrcServiceDesk::StructureRecords.attributes(resource, record) : nil
      record.assign_attributes(data)
      validate_links!(resource, record, !record_id.nil?)
      record.save!
      receipt = audit.write!(resource: resource, record: record, before: before, key: key, fingerprint: fingerprint, reason: reason)
      Result.new(record: record, audit_id: receipt.id)
    end
  end

  def with_authority(resource)
    JrcServiceDesk::Base.transaction do
      initial = fresh_context!
      # Same outer Account lock order as operational commands. No opposite Unit->Account lock.
      Account.where(id: initial.account.id).lock.take!
      User.where(id: initial.user.id).lock('FOR SHARE').take!
      au = AccountUser.where(id: initial.account_user.id, account_id: initial.account.id, user_id: initial.user.id).lock('FOR SHARE').take!
      raise Pundit::NotAuthorizedError unless au.respond_to?(:custom_role) && au.custom_role
      au.custom_role.class.where(id: au.custom_role_id, account_id: initial.account.id).lock('FOR SHARE').take!
      @context = fresh_context!
      raise Pundit::NotAuthorizedError unless @context.allowed?(resource)
      yield
    end
  end

  def fresh_context!
    context = JrcServiceDesk::StructureContext.new(@native_context)
    raise Pundit::NotAuthorizedError unless context.available?
    context
  end

  def authorize!(record, action)
    Pundit.authorize(@context.to_h, record, action, policy_class: JrcServiceDesk::StructurePolicy)
  end

  def validate_links!(resource, record, persisted)
    case resource
    when 'units'
      parent = JrcServiceDesk::OperatorCompany.where(account_id: @context.account.id).lock('FOR SHARE').find(record.operator_company_id)
      raise ArgumentError, 'Inactive operator' if record.active? && !parent.active?
    when 'unit_memberships'
      unit = JrcServiceDesk::Unit.where(account_id: @context.account.id).lock.find(record.unit_id)
      operator = JrcServiceDesk::OperatorCompany.where(account_id: @context.account.id).lock('FOR SHARE').find(unit.operator_company_id)
      recipient = AccountUser.where(account_id: @context.account.id).lock('FOR SHARE').find(record.account_user_id)
      user = User.where(id: recipient.user_id).lock('FOR SHARE').take!
      # Revocation is always possible for an old recipient, including a changed User type.
      if record.active?
        raise ArgumentError, 'Inactive unit/operator' unless unit.active? && operator.active?
        raise Pundit::NotAuthorizedError unless JrcServiceDesk::InitializerAuthority.client_user?(user)
        if recipient.id == @context.account_user.id && (!persisted || record.will_save_change_to_active?)
          raise Pundit::NotAuthorizedError, 'Self grant denied'
        end
      end
    end
  end
end
