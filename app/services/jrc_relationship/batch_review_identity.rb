# Shared header for already-authorized private review projections. This helper
# performs no lookup and grants no right to read a frozen customer audience.
class JrcRelationship::BatchReviewIdentity
  def self.call(review)
    review.attributes.slice('id', 'state', 'revision', 'digest', 'inputs').merge('expires_at' => review.expires_at.iso8601(6))
  end
end
