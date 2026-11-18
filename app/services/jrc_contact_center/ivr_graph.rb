# frozen_string_literal: true

# Authorizes local draft references using the native module and organizational scopes.
class JrcContactCenter::IvrGraph
  attr_reader :data, :nodes, :unit_id

  def initialize(graph, access:, unit_id:)
    @identity = access.policy.user_context.slice(:account, :account_user, :user)
    @access = fresh_access
    raise Pundit::NotAuthorizedError unless @access.policy.configure?

    JrcContactCenter::IvrGraphSchema.validate!(graph)
    @data = graph.deep_dup
    @nodes = @data.fetch('nodes').index_by { |node| node.fetch('id') }
    @unit_id = unit_id.to_s
    validate_ids!
    validate_choices!
    validate_references!(@access)
    JrcContactCenter::IvrGraphPaths.validate!(nodes)
  end

  def authorized_copy
    self.class.new(data, access: @access, unit_id: unit_id)
  end

  private

  def fresh_access
    raise Pundit::NotAuthorizedError unless @identity.values.all?(&:present?) && @identity.length == 3

    context = @identity.transform_values(&:reload)
    JrcContactCenter::AccessScope.new(user_context: context)
  end

  def validate_ids!
    valid = nodes.length == data.fetch('nodes').length && nodes.key?(data.fetch('start'))
    raise JrcContactCenter::OperationError, 'ivr_duplicate_or_missing_node' unless valid
  end

  def validate_choices!
    nodes.each_value do |node|
      next unless node.fetch('type') == 'menu'

      digits = node.fetch('options').pluck('digit')
      raise JrcContactCenter::OperationError, 'ivr_duplicate_dtmf' unless digits.uniq.length == digits.length
    end
  end

  def validate_references!(access)
    validate_unit!(access.units)
    validate_queues!(access.queues)
  end

  def validate_unit!(units)
    valid = unit_id.match?(/\A[1-9]\d{0,18}\z/) && unit_id.to_i.bit_length <= 63
    valid &&= units.exists?(id: unit_id, status: 'active')
    raise ActiveRecord::RecordNotFound unless valid
  end

  def validate_queues!(queues)
    ids = nodes.values.filter_map { |node| node['queue_id'] }.uniq
    raise JrcContactCenter::OperationError, 'ivr_unavailable_queue' unless ids.all? { |id| id.to_i.bit_length <= 63 }

    permitted = queues.where(unit_id: unit_id, id: ids, status: 'active', service_kind: 'voice').pluck(:id).map(&:to_s)
    raise JrcContactCenter::OperationError, 'ivr_unavailable_queue' unless (ids - permitted).empty?
  end
end
