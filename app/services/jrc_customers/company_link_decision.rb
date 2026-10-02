# Pure decision rule shared by operational writes and reviewed backfills.
# Only persisted identifiers supplied by scoped callers are evidence, never names.
class JrcCustomers::CompanyLinkDecision
  class Conflict < ArgumentError; end

  def self.resolve(explicit: nil, candidates: [])
    ids = ([explicit] + candidates).compact.reject { |id| id == '' }.map do |id|
      unless id.is_a?(Integer) || (id.is_a?(String) && id.match?(/\A[1-9][0-9]*\z/))
        raise Conflict, 'Invalid company identifier'
      end
      value = Integer(id)
      raise Conflict, 'Invalid company identifier' unless value.positive? && value <= 9_223_372_036_854_775_807
      value
    end.uniq
    raise Conflict, 'Company differs from the contact or linked origin; review the existing links.' if ids.size > 1

    ids.first
  end
end
