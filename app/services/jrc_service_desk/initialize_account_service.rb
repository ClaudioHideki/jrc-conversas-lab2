# frozen_string_literal: true

# Called only after native SuperAdmin login + nominative authorization + explicit POST.
# This is NOT a Rails initializer, seed or job. All three records and audits commit together.
class JrcServiceDesk::InitializeAccountService
  NAMESPACE = 'jrc_service_desk_initialization_v1'

  def self.marker(account_id)
    "jrc-sd-initialization-#{JrcServiceDesk::Input.id(account_id)}"
  end

  def initialize(account:, actor:)
    @account, @actor = account, actor
  end

  def empty?
    authorize!
    !Audited::Audit.exists?(request_uuid: self.class.marker(@account.id)) &&
      [JrcServiceDesk::OperatorCompany, JrcServiceDesk::Unit, JrcServiceDesk::UnitMembership, JrcServiceDesk::Ticket]
        .none? { |klass| klass.where(account_id: @account.id).exists? }
  end

  def last_receipt_id
    authorize!
    audit = Audited::Audit.where(request_uuid: self.class.marker(@account.id), user_id: @actor.id).first
    return nil unless audit
    summary(audit)
    audit.id
  end

  def candidates(query = '')
    authorize!
    raise Pundit::NotAuthorizedError unless empty?
    raise ArgumentError unless query.is_a?(String) && query.length <= 200
    scope = AccountUser.where(account_id: @account.id).joins(:user).where(users: { type: [nil, ''] })
      .where.not(users: { confirmed_at: nil }).where.not(user_id: [@actor.id] + JrcServiceDesk::InitializerAuthority.ids)
    scope = scope.where('users.name ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(query)}%") unless query.blank?
    scope.order(:id).limit(50).includes(:user)
  end

  def call(input:, idempotency_key:)
    input = JrcServiceDesk::Input.attributes(input, %w[operator unit account_user_id reason confirmed])
    operator_data = JrcServiceDesk::StructureContract.attributes('operator_companies', input.fetch('operator'), create: true)
    # These three fields share the operator text/boolean contract; parent is created below.
    unit_data = JrcServiceDesk::StructureContract.attributes('operator_companies', input.fetch('unit'), create: true)
    raise ArgumentError, 'Initial structure must be explicitly active' unless operator_data['active'] == true && unit_data['active'] == true
    recipient_id = JrcServiceDesk::Input.id(input.fetch('account_user_id'))
    reason = JrcServiceDesk::StructureContract.reason(input.fetch('reason'))
    JrcServiceDesk::StructureContract.confirmation(input.fetch('confirmed'))
    key = JrcServiceDesk::Input.request_key(idempotency_key)
    fingerprint = JrcServiceDesk::CanonicalJson.digest(input.merge('account_user_id' => recipient_id, 'reason' => reason))

    JrcServiceDesk::Base.transaction do
      lock_authority!
      existing = Audited::Audit.where(request_uuid: self.class.marker(@account.id)).first
      if existing
        value = summary(existing)
        raise JrcServiceDesk::IdempotencyConflict unless value['key'] == key && value['fingerprint'] == fingerprint
        next existing.id
      end
      raise JrcServiceDesk::IdempotencyConflict, 'Service Desk structure is not empty' unless empty?
      recipient = AccountUser.where(account_id: @account.id).lock('FOR SHARE').find(recipient_id)
      client = User.where(id: recipient.user_id).lock('FOR SHARE').take!
      raise Pundit::NotAuthorizedError unless client.id != @actor.id && JrcServiceDesk::InitializerAuthority.client_user?(client)

      operator = JrcServiceDesk::OperatorCompany.create!(operator_data.merge('account' => @account))
      unit = JrcServiceDesk::Unit.create!(unit_data.merge('account' => @account, 'operator_company' => operator))
      membership = JrcServiceDesk::UnitMembership.create!(account: @account, unit: unit, account_user: recipient, active: true)
      audit = JrcServiceDesk::StructureAudit.new(account: @account, actor: @actor)
      { 'operator_companies' => operator, 'units' => unit, 'unit_memberships' => membership }.each do |resource, record|
        audit.write!(resource: resource, record: record, before: nil,
          key: "init:#{JrcServiceDesk::CanonicalJson.digest(key)}:#{resource}", fingerprint: fingerprint, reason: reason)
      end
      metadata = { 'namespace' => NAMESPACE, 'account_id' => @account.id, 'author_user_id' => @actor.id,
        'recipient_account_user_id' => recipient.id, 'operator_company_id' => operator.id, 'unit_id' => unit.id,
        'membership_id' => membership.id, 'reason' => reason, 'key' => key, 'fingerprint' => fingerprint,
        'records' => { 'operator_companies' => JrcServiceDesk::StructureRecords.project('operator_companies', operator),
          'units' => JrcServiceDesk::StructureRecords.project('units', unit),
          'unit_memberships' => JrcServiceDesk::StructureRecords.project('unit_memberships', membership) } }
      receipt = Audited::Audit.create!(auditable: unit, associated: unit, user: @actor, action: 'create',
        audited_changes: { 'service_desk_initialization' => metadata.except('key', 'records') },
        comment: JrcServiceDesk::CanonicalJson.dump(metadata), request_uuid: self.class.marker(@account.id))
      receipt.id
    end
  end

  def receipt(audit_id)
    authorize!
    audit = Audited::Audit.where(request_uuid: self.class.marker(@account.id)).find(JrcServiceDesk::Input.id(audit_id))
    info = summary(audit)
    operator = JrcServiceDesk::OperatorCompany.where(account_id: @account.id).find(info.fetch('operator_company_id'))
    unit = JrcServiceDesk::Unit.where(account_id: @account.id, operator_company_id: operator.id).find(info.fetch('unit_id'))
    membership = JrcServiceDesk::UnitMembership.where(account_id: @account.id, unit_id: unit.id,
      account_user_id: info.fetch('recipient_account_user_id')).find(info.fetch('membership_id'))
    info.except('key', 'fingerprint').merge('audit_id' => audit.id.to_s, 'occurred_at' => audit.created_at.iso8601(6),
      'current_records' => { 'operator_companies' => JrcServiceDesk::StructureRecords.project('operator_companies', operator),
        'units' => JrcServiceDesk::StructureRecords.project('units', unit),
        'unit_memberships' => JrcServiceDesk::StructureRecords.project('unit_memberships', membership) })
  end

  private

  def authorize!
    Pundit.authorize({ account: @account, initializer: @actor }, @account, :show?, policy_class: JrcServiceDesk::InitializationPolicy)
  end

  def lock_authority!
    authorize!
    @account = Account.where(id: @account.id).lock.take!
    @actor = SuperAdmin.where(id: @actor.id).lock('FOR SHARE').take!
    authorize!
  end

  def summary(audit)
    value = JSON.parse(audit.comment.to_s)
    raise ActiveRecord::RecordNotFound unless value.is_a?(Hash) && value['namespace'] == NAMESPACE &&
      value['account_id'] == @account.id && value['author_user_id'] == @actor.id && audit.user_id == @actor.id
    value
  rescue JSON::ParserError
    raise ActiveRecord::RecordNotFound
  end
end
