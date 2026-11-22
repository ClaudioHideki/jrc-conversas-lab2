# frozen_string_literal: true

# Deterministic local simulation only. No provider command, recording or call is created.
class JrcContactCenter::IvrSimulator
  MAX_STEPS = 256

  def initialize(graph:)
    @graph = graph
  end

  def call(input: '', at: nil)
    @graph = @graph.authorized_copy
    raise JrcContactCenter::OperationError, 'ivr_invalid_simulation_input' unless input.is_a?(String) && input.match?(/\A[0-9*#]{0,128}\z/)

    @instant = at
    @digits = input.chars
    @attempts = Hash.new(0)
    @trace = []
    traverse
  end

  private

  def traverse
    current = @graph.data.fetch('start')
    MAX_STEPS.times do
      node = @graph.nodes.fetch(current)
      @trace << { node_id: current, type: node.fetch('type') }
      return result(node.fetch('type') == 'end' ? 'ended' : 'queue_destination', node['queue_id']) if %w[end queue].include?(node.fetch('type'))

      current = node.fetch('type') == 'calendar' ? calendar_target(node) : next_target(node)
    end
    result('step_limit')
  end

  def calendar_target(node)
    decision = JrcContactCenter::IvrCalendarDecision.new(node.fetch('calendar_reference')).call(instant: @instant)
    @trace.last[:calendar] = decision
    transition(decision.fetch('open') ? 'calendar_open' : 'calendar_closed', node.fetch(decision.fetch('open') ? 'on_open' : 'on_closed'))
  end

  def next_target(node)
    digit = @digits.shift
    return transition('timeout', node.fetch('on_timeout')) unless digit

    choice = node.fetch('options').find { |option| option.fetch('digit') == digit }
    if choice
      @attempts[node.fetch('id')] = 0
      return transition('matched_option', choice.fetch('target'))
    end
    @attempts[node.fetch('id')] += 1
    limit = @attempts[node.fetch('id')] >= node.fetch('max_attempts')
    transition(limit ? 'invalid_limit' : 'retry_invalid', limit ? node.fetch('on_invalid') : node.fetch('id'))
  end

  def transition(event, target)
    @trace.last[:event] = event
    target
  end

  def result(outcome, queue_id = nil)
    { local_only: true, provider_applied: false, outcome: outcome, queue_id: queue_id, trace: @trace }
  end
end
