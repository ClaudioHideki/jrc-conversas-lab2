# frozen_string_literal: true

# Native states retained; new states are explicit and never affect linked tickets.
module JrcServiceDesk::IncidentWorkflow
  STATUSES = %w[open investigating in_progress waiting monitoring resolved closed].freeze
  ACTIVE = %w[open investigating in_progress waiting monitoring].freeze
  TRANSITIONS = ACTIVE.index_with { |state| (ACTIVE - [state]) + ['resolved'] }.merge('resolved' => ['closed'], 'closed' => []).freeze
  module_function

  def action_for(from, target)
    raise ArgumentError, 'Invalid state transition' unless TRANSITIONS.fetch(from, []).include?(target)
    return :resolve? if target == 'resolved'
    return :close? if target == 'closed'

    :work?
  end

  def validate!(from:, target:, resolution: nil)
    action = action_for(from, target)
    if %w[resolved closed].include?(target) && !(resolution.is_a?(String) && resolution.strip.length.between?(1, 20_000))
      raise ArgumentError, 'Resolution summary required'
    end

    action
  end

  def reopen!(from:, reason:)
    raise ArgumentError, 'Only terminal records may reopen' unless %w[resolved closed].include?(from)
    raise ArgumentError, 'Reopening reason required' unless reason.is_a?(String) && reason.strip.length.between?(1, 4000)

    'investigating'
  end
end
