# frozen_string_literal: true
require 'minitest/autorun'
module JrcServiceDesk; end
require_relative '../../app/services/jrc_service_desk/history_projection'

class ServiceDeskHistoryProjectionTest < Minitest::Test
  def payload
    { 'note' => 'private', 'solution' => 'private answer', 'fields' => { 'internal' => true },
      'evidence_note_ids' => [10], 'sla' => { 'snapshot_id' => 42 }, 'reason_code' => 'customer',
      'from_phase' => 'open', 'to_phase' => 'resolved', 'policy_digest' => 'digest', 'credential' => 'not projected' }
  end

  [true, false].product([true, false]).each do |notes, sla|
    define_method("test_projection_notes_#{notes}_sla_#{sla}") do
      projected = JrcServiceDesk::HistoryProjection.lifecycle(payload, notes: notes, sla: sla)
      %w[note solution fields evidence_note_ids].each { |key| assert_equal notes, projected.key?(key) }
      assert_equal sla, projected.key?('sla')
      %w[reason_code from_phase to_phase policy_digest].each { |key| assert_equal payload[key], projected[key] }
      refute projected.key?('credential')
      assert_equal 'private', payload['note']
    end
  end

  def test_empty_protected_payload_is_not_a_note
    assert_equal false, JrcServiceDesk::HistoryProjection.protected_input?('note' => '', 'solution' => nil, 'fields' => {}, 'evidence_note_ids' => [])
    assert_equal false, JrcServiceDesk::HistoryProjection.protected_input?('reason_code' => 'configured')
  end

  def test_every_nonempty_protected_field_requires_note_visibility
    [{ 'note' => 'a' }, { 'solution' => 'b' }, { 'fields' => { 'approved' => false } }, { 'evidence_note_ids' => [3] }].each do |item|
      assert JrcServiceDesk::HistoryProjection.protected_input?(item)
    end
  end
end
