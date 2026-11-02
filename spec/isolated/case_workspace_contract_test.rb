# frozen_string_literal: true

require 'minitest/autorun'
module JrcServiceDesk; end
require_relative '../../app/services/jrc_service_desk/input'
require_relative '../../app/services/jrc_service_desk/incident_workflow'
require_relative '../../app/services/jrc_service_desk/case_input'
class CaseWorkspaceContractTest < Minitest::Test
  def test_creation_does_not_require_cause_confirmed
    assert_equal 'New', JrcServiceDesk::CaseInput.call({ title: 'New', severity: 'normal', resource_kind: 'problem' }, creating: true)['title']
  end

  def test_unknown_fields_rejected
    assert_raises(ArgumentError) { JrcServiceDesk::CaseInput.call({ title: 'New', account_id: 12 }) }
  end

  def test_impacts_are_not_priorities
    assert_equal 'widespread', JrcServiceDesk::CaseInput.call({ details: { impact_level: 'widespread' } })['details']['impact_level']
    assert_raises(ArgumentError) { JrcServiceDesk::CaseInput.call({ details: { impact_level: 'critical' } }) }
  end

  def test_resolution_and_closure_are_separate
    assert_equal :resolve?, JrcServiceDesk::IncidentWorkflow.validate!(from: 'open', target: 'resolved', resolution: 'Fixed')
    assert_equal :close?, JrcServiceDesk::IncidentWorkflow.validate!(from: 'resolved', target: 'closed', resolution: 'Fixed')
    assert_raises(ArgumentError) { JrcServiceDesk::IncidentWorkflow.validate!(from: 'open', target: 'closed', resolution: 'Fixed') }
  end

  def test_terminal_requires_nonempty_solution
    [nil, '', ' '].each do |value|
      assert_raises(ArgumentError) do
        JrcServiceDesk::IncidentWorkflow.validate!(from: 'open', target: 'resolved', resolution: value)
      end
    end
  end

  def test_internal_transitions_require_work_permission
    assert_equal :work?, JrcServiceDesk::IncidentWorkflow.validate!(from: 'open', target: 'investigating')
  end

  def test_reopen_requires_reason_and_terminal_state
    assert_equal 'investigating', JrcServiceDesk::IncidentWorkflow.reopen!(from: 'closed', reason: 'Recurrence')
    assert_raises(ArgumentError) { JrcServiceDesk::IncidentWorkflow.reopen!(from: 'closed', reason: '') }
    assert_raises(ArgumentError) { JrcServiceDesk::IncidentWorkflow.reopen!(from: 'open', reason: 'Recurrence') }
  end

  def test_date_requires_offset
    assert_raises(ArgumentError) { JrcServiceDesk::CaseInput.call({ started_at: '2026-10-24T10:00:00' }) }
    assert_equal(-10_800, JrcServiceDesk::CaseInput.call({ started_at: '2026-10-24T10:00:00-03:00' })['started_at'].utc_offset)
  end

  def test_link_selection_bounded_and_deduplicated
    assert_equal [1, 2], JrcServiceDesk::CaseInput.ids(%w[2 1])
    assert_raises(ArgumentError) { JrcServiceDesk::CaseInput.ids(%w[1 1]) }
    assert_raises(ArgumentError) { JrcServiceDesk::CaseInput.ids([]) }
    assert_raises(ArgumentError) { JrcServiceDesk::CaseInput.ids((1..101).to_a) }
  end

  def test_text_lengths_and_titles
    assert_raises(ArgumentError) { JrcServiceDesk::CaseInput.call(title: ' ') }
    assert_raises(ArgumentError) { JrcServiceDesk::CaseInput.call(description: 'x' * 20_001) }
  end
end
