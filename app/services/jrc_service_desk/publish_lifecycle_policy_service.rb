# frozen_string_literal: true

class JrcServiceDesk::PublishLifecyclePolicyService < JrcServiceDesk::BaseService
  def call(unit_id:, attributes:)
    values = JrcServiceDesk::Input.attributes(attributes, %w[name service_id enabled expected_version definition])
    raise ArgumentError, 'Explicit enabled flag required' unless [true, false].include?(values['enabled'])
    expected = JrcServiceDesk::Input.version(values.fetch('expected_version'))
    definition = JrcServiceDesk::CanonicalJson.normalize(values.fetch('definition'))
    rules = JrcServiceDesk::LifecycleRules.new(definition)
    with_unit(unit_id) do |unit|
      service = if values['service_id']
                  JrcServiceDesk::Service.where(account_id: context.account.id, unit_id: unit.id)
                    .lock('FOR SHARE').find(JrcServiceDesk::Input.id(values['service_id']))
                end
      raise ArgumentError, 'Cannot enable policy for inactive service' if service && !service.active? && values['enabled']
      policy = JrcServiceDesk::LifecyclePolicy.find_or_initialize_by(account: context.account, unit: unit, service: service)
      authorize!(policy, :publish?)
      current_number = policy.current_version&.version || 0
      raise JrcServiceDesk::IdempotencyConflict, 'Policy version changed; reload before publishing' unless expected == current_number
      phases = if !values['enabled'] && policy.current_version && definition == policy.current_version.definition
                 policy.current_version.status_phases
               else
                 validate_statuses!(rules, unit)
               end
      policy.name = text(values.fetch('name'))
      policy.enabled = values['enabled']
      policy.save!
      version = policy.versions.build(account: context.account, unit: unit, actor_membership: actor_membership,
        version: current_number + 1, definition: definition, status_phases: phases,
        publication: { 'name' => policy.name, 'enabled' => policy.enabled, 'service_id' => policy.service_id })
      version.digest = version.expected_digest
      version.save!
      policy.update!(current_version: version)
      policy
    end
  end

  private

  def validate_statuses!(rules, unit)
    ids = rules.definition['transitions'].flat_map { |r| r['from_status_ids'] + [r['to_status_id']] }
    ids += rules.definition['pause_reasons'].flat_map { |r| r['status_ids'] }
    statuses = JrcServiceDesk::TicketStatus.where(account_id: context.account.id, unit_id: unit.id, id: ids.uniq, active: true).lock('FOR SHARE').to_a
    raise ActiveRecord::RecordNotFound, 'Policy status outside active unit configuration' unless statuses.map(&:id).sort == ids.uniq.sort
    phases = statuses.to_h { |record| [record.id.to_s, record.phase] }
    targets = { 'pause' => 'waiting', 'resume' => 'open', 'resolve' => 'resolved', 'close' => 'closed', 'cancel' => 'cancelled', 'reopen' => 'open', 'work_status' => 'open' }
    sources = { 'pause' => %w[open], 'resume' => %w[waiting], 'resolve' => %w[open waiting], 'close' => %w[resolved], 'cancel' => %w[open waiting resolved], 'reopen' => %w[resolved closed cancelled], 'work_status' => %w[open] }
    rules.definition['transitions'].each do |rule|
      raise ArgumentError, 'Target phase incompatible with business action' unless phases[rule['to_status_id'].to_s] == targets.fetch(rule['action'])
      raise ArgumentError, 'Source phase incompatible with business action' unless rule['from_status_ids'].all? { |id| sources.fetch(rule['action']).include?(phases[id.to_s]) }
      if rule['action'] == 'pause' && rules.definition['pause_reasons'].none? { |reason| reason['status_ids'].include?(rule['to_status_id']) }
        raise ArgumentError, 'Pause needs an explicit reason for its target status'
      end
      raise ArgumentError, 'Reopen explicitly disabled' if rule['action'] == 'reopen' && !rules.definition['reopen']['allowed']
    end
    phases
  end
end
