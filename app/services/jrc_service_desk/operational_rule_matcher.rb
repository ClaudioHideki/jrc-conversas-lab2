# frozen_string_literal: true

require_relative 'operational_rule_conditions'

# Explicit numeric precedence; equal-precedence matches are an error, not a guess.
class JrcServiceDesk::OperationalRuleMatcher
  class Ambiguous < ArgumentError; end

  def self.call(rows, facts, now: Time.now.utc)
    matches = rows.select { |row| JrcServiceDesk::OperationalRuleConditions.match?(row, facts, now: now) }
    return nil if matches.empty?

    precedence = matches.map { |row| row.fetch('precedence') }.min
    winners = matches.select { |row| row['precedence'] == precedence }
    raise Ambiguous, 'Matching rules have equal precedence' unless winners.one?

    winners.first
  end
end
