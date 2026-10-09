class JrcNico::Helpdesk::Context
  attr_reader :member, :access, :native

  def initialize(member)
    raise Pundit::NotAuthorizedError unless member.is_a?(AccountUser) && member.persisted?

    @member = AccountUser.find(member.id)
    @access = JrcNico::OperationalAccess.new(account: @member.account, user: @member.user).authorize!
    @native = JrcServiceDesk::OperationalContext.new(account: @member.account, user: @member.user, account_user: @member)
    raise Pundit::NotAuthorizedError unless @native.capability?(:module_view)
  end

  def account
    member.account
  end

  def administrator!
    refresh!
    raise Pundit::NotAuthorizedError unless native.administrator?

    self
  end

  def refresh!
    initialize(AccountUser.find(member.id))
    self
  end

  def ticket(id)
    JrcNico::DomainAccess.new(access).ticket(id)
  end

  def tickets
    JrcOperations::Access.tickets(member)
  end

  def policy(id)
    JrcNico::Helpdesk::PolicyVersion.where(account: account).find(id)
  end

  def event(id)
    refresh!
    value = JrcNico::Helpdesk::Event.where(account: account).find(id)
    parent = ticket(value.ticket_id)
    authorize_event_details!(value, parent)
    authorize_event_resources!(value)
    JrcNico::Helpdesk::EvidenceAccess.new(self, parent, value.evidence).call
    authorize_legal_event!(value) if value.rule_key == 'R11'
    value
  end

  def validate_definition_scope!(definition)
    refresh!
    validate_pilot_scope!(definition)
    validate_recipients!(definition)
    validate_priorities!(definition)
    validate_priority_targets!(definition)
    true
  end

  private

  def authorize_event_details!(value, parent)
    Pundit.authorize(native.to_h, parent, :view_sla?) if %w[R05 R06 R07 R08 R09].include?(value.rule_key)
    Pundit.authorize(native.to_h, parent, :view_notes?) if %w[R10 R11].include?(value.rule_key)
    Pundit.authorize(native.to_h, parent, :view_history?) if value.rule_key == 'R14'
    value.evidence.fetch('evidence_note_ids', []).each do |id|
      Pundit.authorize(native.to_h, parent.ticket_notes.find(id), :show?)
    end
  end

  def authorize_event_resources!(value)
    %w[previous_ticket_ids ticket_ids occurrence_ids].each { |key| Array(value.evidence[key]).each { |id| ticket(id) } }
  end

  def authorize_legal_event!(value)
    recipients = %w[legal thiago ceo].flat_map { |key| value.policy_version.definition.fetch('roles').fetch(key) }
    raise Pundit::NotAuthorizedError unless native.administrator? || member.id == value.actor_id || recipients.include?(member.id)
  end

  def validate_pilot_scope!(definition)
    assert_ids!(native.view_unit_scope, definition.fetch('unit_ids'))
    assert_ids!(JrcCustomers::Company.where(account: account), definition.fetch('company_ids'))
    assert_ids!(account.account_users, definition.fetch('operator_ids'))

    critical = definition.dig('rules', 'R12', 'critical_company_ids')
    raise Pundit::NotAuthorizedError unless (critical - definition.fetch('company_ids')).empty?
  end

  def assert_ids!(relation, ids)
    raise Pundit::NotAuthorizedError unless relation.where(id: ids).pluck(:id).sort == ids.sort
  end

  def validate_recipients!(definition)
    recipients = definition['rules'].values.flat_map do |rule|
      rule['recipients']
    end + definition.dig('daily', 'recipients') + definition['roles'].values.flatten
    raise Pundit::NotAuthorizedError unless (recipients.uniq - account.account_users.pluck(:id)).empty?
  end

  def validate_priorities!(definition)
    definition.fetch('priority_order').each do |unit_id, ids|
      actual = JrcServiceDesk::Priority.where(account: account, unit_id: unit_id, active: true, id: ids).pluck(:id)
      raise Pundit::NotAuthorizedError unless actual.sort == ids.sort
    end
  end

  def validate_priority_targets!(definition)
    definition.dig('rules', 'R12', 'priority_ids').each do |unit_id, id|
      raise Pundit::NotAuthorizedError unless definition.fetch('unit_ids').include?(unit_id.to_i)
      raise Pundit::NotAuthorizedError unless JrcServiceDesk::Priority.exists?(account: account, unit_id: unit_id, id: id, active: true)
    end
  end
end
