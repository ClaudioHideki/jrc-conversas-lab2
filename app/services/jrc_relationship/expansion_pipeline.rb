class JrcRelationship::ExpansionPipeline
  def self.open(scope, deals)
    candidates = scope.where(status: %w[suggested approved converted])
    candidates.where(deal_id: nil).or(candidates.where(deal_id: deals.where(status: 'open').select(:id)))
  end
end
