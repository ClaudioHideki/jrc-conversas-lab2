# frozen_string_literal: true

class JrcServiceDesk::OperationalRuleReferences
  UNIT_REFERENCES = {
    'service_id' => JrcServiceDesk::Service, 'category_id' => JrcServiceDesk::Category,
    'priority_id' => JrcServiceDesk::Priority, 'queue_id' => JrcServiceDesk::Queue, 'ticket_type_id' => JrcServiceDesk::TicketType,
    'subcategory_id' => JrcServiceDesk::Category
  }.freeze

  def initialize(context:, unit:, active: true)
    @context = context
    @unit = unit
    @active = active
  end

  def validate!(kind, definition)
    if kind == 'approval_deadline'
      verify_deadline!(definition)
    elsif kind != 'recurrence'
      definition.fetch('rules').each do |rule|
        next if rule['enabled'] == false

        validate_rule!(rule)
        if kind == 'sla_selection'
          verify_snapshot!(rule['output']['snapshot'])
          services = rule['match'].key?('service_id') ? [rule['match']['service_id']] :
            JrcServiceDesk::LifecyclePolicy.where(account_id: @context.account.id, unit_id: @unit.id, enabled: true).pluck(:service_id).push(nil).uniq
          services.each do |service_id|
            ticket = JrcServiceDesk::Ticket.new(account_id: @context.account.id, unit_id: @unit.id, service_id: service_id)
            version = JrcServiceDesk::LifecycleSelector.new(ticket).applicable
            next unless version && version.definition.dig('sla', 'mode') == 'calendar_snapshot'
            verify_snapshot!(rule['output']['snapshot'], clock_kinds: version.rules.clock_kinds)
          end
        end
      end
    end
  end

  def validate_rule!(rule)
    validate_facts!(rule.fetch('match'))
    JrcServiceDesk::OperationalRuleConditions.predicates(rule).each { |item| validate_facts!(item['field'] => item['value']) }
    JrcServiceDesk::OperationalRuleConditions.predicates(rule).select { |item| item['field'] == 'form_value' }.each do |item|
      service = JrcServiceDesk::Service.where(account: @context.account, unit: @unit).find(JrcServiceDesk::Input.id(rule.fetch('match').fetch('service_id')))
      field = service.form_fields.find { |row| row['key'] == item['value']['key'] } || raise(ArgumentError, 'Unknown source service form field')
      JrcServiceDesk::CatalogueAnswers.new([field.merge('required' => true)]).validate!(field['key'] => item['value']['value'])
    end
    validate_facts!(rule.fetch('output'))
    validate_facts!(rule['output']['classification']) if rule['output']['classification']
    output = rule['output']
    if output['classification']
      raise Pundit::NotAuthorizedError unless @context.capability?(:tickets_edit)
      raise Pundit::NotAuthorizedError if output['classification']['priority_id'] && !@context.capability?(:priority_change)
    end
    if output['label_ids']
      raise Pundit::NotAuthorizedError unless @context.capability?(:tickets_edit)
      raise ActiveRecord::RecordNotFound unless @context.account.labels.where(id: output['label_ids']).count == output['label_ids'].size
    end
    assignment = output['assignment']
    if assignment
      if assignment['fallback_queue_id']
        validate_facts!('queue_id' => assignment['fallback_queue_id'])
        raise Pundit::NotAuthorizedError unless @context.capability?(:tickets_transfer)
      end
      if assignment['account_user_id']
        member = JrcServiceDesk::UnitMembership.operational.where(account: @context.account, unit: @unit, active: true)
          .find_by!(account_user_id: assignment['account_user_id'])
        target = JrcServiceDesk::OperationalContext.new(account: @context.account, user: member.account_user.user, account_user: member.account_user)
        raise Pundit::NotAuthorizedError unless target.unit_allowed?(@unit) && target.capability?(:tickets_view)
        queue = JrcServiceDesk::Queue.where(account: @context.account, unit: @unit).find(output['queue_id'])
        raise Pundit::NotAuthorizedError if queue.team_id && !target.native_team_ids.exists?(id: queue.team_id)
      end
    end
    if rule['exceptions']
      rule['exceptions']['company_ids'].each { |id| validate_facts!('company_id' => id) }
      rule['exceptions']['contract_ids'].each { |id| validate_facts!('contract_id' => id) }
    end
    raise Pundit::NotAuthorizedError if rule['output']['task'] && !@context.capability?(:tasks_manage)
    raise Pundit::NotAuthorizedError if rule['output']['internal_note'] && !@context.capability?(:notes_add)
  end

  def validate_facts!(values)
    UNIT_REFERENCES.each do |field, model|
      next unless values.key?(field)

      scope = model.where(account_id: @context.account.id, unit_id: @unit.id)
      scope = scope.where(active: true) if @active
      scope.lock('FOR SHARE').find(values[field])
    end
    verify_inbox!(values['inbox_id']) if values['inbox_id']
    verify_company!(values['company_id']) if values['company_id']
    @context.account.labels.find(values['label_id']) if values['label_id']
    return unless values['contract_id']

    contract = JrcServiceDesk::CatalogueContracts.new(@context).scope.find(values['contract_id'])
    if values['company_id'] && JrcServiceDesk::CatalogueContracts.company_id(contract) != values['company_id']
      raise Pundit::NotAuthorizedError, 'Contract and customer scopes differ'
    end
  end

  def verify_snapshot!(attributes, clock_kinds: nil)
    keys = JrcServiceDesk::RecordSlaSnapshotService::FIELDS - ['captured_at']
    values = JrcServiceDesk::Input.attributes(attributes, keys)
    raise ArgumentError, 'All snapshot conditions required' unless (keys - values.keys).empty?

    snapshot = JrcServiceDesk::SlaSnapshot.new(values.merge(account: @context.account, unit: @unit))
    JrcServiceDesk::LifecycleClocks.verify_snapshot!(snapshot, clock_kinds: clock_kinds)
    snapshot.expected_digest # also checks canonical JSON types/limits
  rescue JrcServiceDesk::LifecycleDependencyError
    raise ArgumentError, 'Published snapshot requires a valid calendar and matching budgets'
  end

  private

  def verify_inbox!(id)
    inbox = Inbox.where(account_id: @context.account.id).find(id)
    JrcServiceDesk::NativeExecutionContext.with(@context.to_h) { Pundit.authorize(@context.to_h, inbox, :show?) }
  end

  def verify_company!(id)
    raise Pundit::NotAuthorizedError unless @context.capability?(:customers_view)

    Pundit.authorize(@context.to_h, :directory, :access?, policy_class: JrcCustomers::DirectoryPolicy)
    JrcCustomers::Company.where(account_id: @context.account.id).find(id)
  end

  def verify_deadline!(definition)
    member = AccountUser.where(account_id: @context.account.id).find(definition.fetch('executor_account_user_id'))
    executor = JrcServiceDesk::OperationalContext.new(account: @context.account, user: member.user, account_user: member)
    unless executor.operational_unit_allowed?(@unit) && executor.capability?(:approvals_request) &&
           executor.capability?(:approvals_view) && executor.capability?(:tickets_view_all)
      raise Pundit::NotAuthorizedError, 'Deadline executor is not currently authorized'
    end

    JrcServiceDesk::ApprovalTarget.new(context: executor, unit: @unit).attributes(definition.fetch('target'))
  end
end
