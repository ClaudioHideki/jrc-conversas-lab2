# frozen_string_literal: true

# Explicit numeric precedence; equal-precedence matches are an error, not a guess.
class JrcServiceDesk::OperationalRuleMatcher
  class Ambiguous < ArgumentError; end

  def self.call(rows, facts)
    matches = rows.select { |row| row.fetch('match').all? { |key, value| !facts[key].nil? && facts[key] == value } }
    return nil if matches.empty?

    precedence = matches.map { |row| row.fetch('precedence') }.min
    winners = matches.select { |row| row['precedence'] == precedence }
    raise Ambiguous, 'Matching rules have equal precedence' unless winners.one?

    winners.first
  end
end
