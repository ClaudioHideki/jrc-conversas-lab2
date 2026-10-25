# frozen_string_literal: true

# Structural contract for a composition; the individual engines remain the
# authority for capabilities, domain validation, immutable versions and clocks.
class JrcServiceDesk::AutomationComposition
  FAMILIES = %w[routing priority_matrix sla_selection].freeze
  attr_reader :values

  def initialize(attributes)
    @values = JrcServiceDesk::CanonicalJson.normalize(JrcServiceDesk::Input.attributes(attributes, %w[kind code name description service_id enabled definition]))
    raise ArgumentError, 'Explicit kind required' unless %w[lifecycle operational].include?(values['kind'])

    JrcServiceDesk::OperationalRuleContract.token!(values['code'])
    raise ArgumentError, 'Name required' unless values['name'].is_a?(String) && values['name'].strip.length.between?(1, 255)
    raise ArgumentError, 'Invalid description' unless values['description'].is_a?(String) && values['description'].length <= 4000
    raise ArgumentError, 'Explicit activation required' unless [true, false].include?(values['enabled'])

    values['service_id'] = JrcServiceDesk::Input.id(values['service_id']) if values['service_id']
    raise ArgumentError, 'Composition too large' if values.to_json.bytesize > 100_000
    raise ArgumentError, 'Credentials are not policy configuration' if JrcServiceDesk::OperationalRuleContract.credential_key?(values)

    definition = JrcServiceDesk::Input.attributes(values.fetch('definition'), %w[lifecycle families queues notifications])
    raise ArgumentError unless definition.keys.sort == %w[families lifecycle notifications queues].sort
    raise ArgumentError if values['kind'] == 'operational' && definition['lifecycle']
    raise ArgumentError if values['kind'] == 'lifecycle' && !definition['lifecycle'].is_a?(Hash)

    JrcServiceDesk::LifecycleRules.new(definition['lifecycle']) if definition['lifecycle']
    families = JrcServiceDesk::Input.attributes(definition['families'], FAMILIES)
    raise ArgumentError if values['kind'] == 'operational' && !families.key?('routing')

    families.each do |kind, data|
      JrcServiceDesk::OperationalRuleContract.validate!(kind, data)
      data['rules'].each do |row|
        raise ArgumentError, 'Positive precedence required' unless row['precedence'].positive?
        if row['match'].empty? && !row['conditions']
          raise ArgumentError, 'Choose explicit conditions; implicit global rules are not permitted in the visual studio'
        end
        if values['service_id'] && row['match']['service_id'] != values['service_id']
          raise ArgumentError, 'Rule must retain the selected service scope'
        end
      end
    end
    %w[queues notifications].each do |key|
      raise ArgumentError unless definition[key].is_a?(Array) && definition[key].length <= 20
    end
    definition['queues'].each do |row|
      JrcServiceDesk::OperationalRuleContract.fields!(row, %w[id attributes])
      JrcServiceDesk::Input.id(row['id'])
      JrcServiceDesk::ConfigurationContract.attributes('queues', row['attributes'], create: false)
    end
    definition['notifications'].each do |row|
      %w[ticket_type_id service_id inbox_id].each { |field| row[field] = row[field] ? JrcServiceDesk::Input.id(row[field]) : nil }
    end
    keys = definition['notifications'].map { |row| JrcServiceDesk::CanonicalJson.digest(row.slice('event_type', 'channel', 'ticket_type_id', 'service_id')) }
    raise ArgumentError, 'Duplicate notification scope' unless keys.uniq == keys
    raise ArgumentError if definition['queues'].map { |row| row['id'].to_s }.uniq.length != definition['queues'].length
    values['definition'] = JrcServiceDesk::CanonicalJson.normalize(definition)
  end

  def prefix
    "studio.#{JrcServiceDesk::CanonicalJson.digest(values.slice('kind', 'code'))[0, 16]}."
  end

  def merge_family(kind, current)
    others = current ? current.definition.fetch('rules').reject { |row| row['key'].start_with?(prefix) } : []
    others = others.map { |row| row.merge('enabled' => false) } if current && !current.enabled?
    own = values['definition']['families'].fetch(kind).fetch('rules').map do |row|
      row.merge('key' => prefix + JrcServiceDesk::CanonicalJson.digest(row['key'])[0, 16], 'enabled' => values['enabled'] && row.fetch('enabled', true))
    end
    { 'rules' => others + own }
  end
end
