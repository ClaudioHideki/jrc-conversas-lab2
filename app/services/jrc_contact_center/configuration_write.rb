# frozen_string_literal: true

# Preserve the native request contract while serializing scope-sensitive writes.
class JrcContactCenter::ConfigurationWrite
  def initialize(account:, access:)
    @account = account
    @access = access
  end

  def create!(model, &attributes)
    model.transaction do
      model.uncached do
        values = attributes.call
        lock_parents(model.new(values.merge(account: @account)), values)
        model.create!(attributes.call.merge(account: @account))
      end
    end
  end

  def update!(relation, id, &attributes)
    relation.klass.transaction do
      relation.klass.uncached do
        record = relation.find(id)
        record.with_lock do
          relation.find(id)
          lock_parents(record, attributes.call)
          relation.find(id)
          record.update!(attributes.call)
        end
        record
      end
    end
  end

  private

  def lock_parents(record, attributes)
    queues = if record.is_a?(JrcContactCenter::QueueMembership)
               ids = [record.queue_id, attributes[:queue_id]].compact.map(&:to_i).uniq.sort
               @access.queues.order(:id).lock('FOR NO KEY UPDATE').find(ids)
             else
               []
             end
    units = unit_ids(record, attributes, queues).compact.map(&:to_i).uniq.sort
    @access.units.order(:id).lock('FOR NO KEY UPDATE').find(units)
  end

  def unit_ids(record, attributes, queues)
    return [record.parent_unit_id, attributes[:parent_unit_id]] if record.is_a?(JrcContactCenter::Unit)
    return [record.unit_id, attributes[:unit_id]] if record.is_a?(JrcContactCenter::Queue)

    queues.map(&:unit_id)
  end
end
