# Prospective grants only: existing histories are not rewritten.
class JrcApprovals::DelegationTopology
  def self.check!(relation:, principal_id:, delegate_id:, period:)
    raise JrcApprovals::Error, 'INVALID_DELEGATION' if principal_id == delegate_id

    links = relation.where('starts_at < ? AND ends_at > ?', period.last, period.first)
                    .pluck(:principal_id, :delegate_id, :starts_at, :ends_at).group_by(&:first)
    raise JrcApprovals::Error, 'INVALID_DELEGATION' if new(links).reaches?(delegate_id, principal_id, period)
  end

  def initialize(links)
    @links = links
  end

  def reaches?(source, target, period)
    pending = [[source, period]]
    seen = Hash.new { |memo, node| memo[node] = [] }
    until pending.empty?
      node, window = pending.pop
      next if seen[node].any? { |previous| previous.first <= window.first && previous.last >= window.last }
      return true if node == target

      seen[node] << window
      pending.concat(successors(node, window))
    end
    false
  end

  private

  def successors(node, window)
    @links.fetch(node, []).filter_map do |_, recipient, starts_at, ends_at|
      overlap = [[window.first, starts_at].max, [window.last, ends_at].min]
      [recipient, overlap] if overlap.first < overlap.last
    end
  end
end
