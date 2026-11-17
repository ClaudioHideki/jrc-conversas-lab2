# frozen_string_literal: true

# Preserve the native request contract while serializing scope-sensitive writes.
class JrcContactCenter::ConfigurationWrite
  UNSPECIFIED_REVISION = Object.new.freeze

  def initialize(account:, access:, reauthorize: nil)
    @account = account
    @access = access
    @reauthorize = reauthorize
  end

  def create!(model)
    model.transaction do
      model.uncached do
        reauthorize!(nil)
        values = yield
        proposed = model.new(values.merge(account: @account))
        lock_parents(proposed, values)
        reauthorize!(proposed)
        model.create!(yield.merge(account: @account))
      end
    end
  end

  def update!(relation, id, expected_revision: UNSPECIFIED_REVISION)
    relation.klass.transaction do
      relation.klass.uncached do
        record = relation.find(id)
        record.with_lock do
          relation.find(id)
          reauthorize!(record)
          lock_parents(record, yield)
          relation.find(id)
          reauthorize!(record)
          JrcContactCenter::ConfigurationRevision.check!(record, expected_revision) unless expected_revision.equal?(UNSPECIFIED_REVISION)
          record.update!(yield)
        end
        record
      end
    end
  end

  private

  def reauthorize!(record)
    @access = @reauthorize.call(record) if @reauthorize
  end

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
