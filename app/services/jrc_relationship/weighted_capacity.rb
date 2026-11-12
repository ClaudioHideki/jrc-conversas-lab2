class JrcRelationship::WeightedCapacity
  def self.facts(pool:, target:, inputs:, applied_ids:, unit:)
    baseline = target.where.not(id: applied_ids)
    selected = pool.where(id: inputs.fetch('ids'))
    incoming = selected.where.not(owner_id: inputs.fetch('owner_id')).or(selected.where(owner_id: nil))
    applied = pool.where(id: applied_ids, owner_id: inputs.fetch('owner_id'))
    current = JrcRelationship::CapacityWorkload.sum(baseline, unit)
    load = JrcRelationship::CapacityWorkload.sum(incoming, unit) + JrcRelationship::CapacityWorkload.sum(applied, unit)
    { 'current' => current.to_f, 'incoming' => load.to_f, 'incoming_customers' => incoming.count + applied.count,
      'projected' => (current + load).to_f, 'baseline_digest' => baseline_digest(baseline) }
  end

  def self.baseline_digest(baseline)
    digest = Digest::SHA256.new
    baseline.order(:id).find_each do |record|
      digest << JrcServiceDesk::CanonicalJson.dump([record.id, record.settings.fetch('capacity_workload', {})])
    end
    digest.hexdigest
  end
end
