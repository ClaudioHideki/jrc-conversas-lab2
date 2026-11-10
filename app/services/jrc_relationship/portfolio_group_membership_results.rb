class JrcRelationship::PortfolioGroupMembershipResults
  def self.call(ids:, before:, after:, active:)
    old = before.to_h
    current = after.to_h
    ids.map do |id|
      changed = old.fetch(id, false) != current.fetch(id, false)
      state = if active
                changed ? 'linked' : 'already_linked'
              else
                changed ? 'unlinked' : 'already_unlinked'
              end
      { assignment_id: id, state: state }
    end
  end
end
