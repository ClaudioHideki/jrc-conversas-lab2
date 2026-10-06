# Tests the native Agenda projection without Rails boot, database queries or timezone infrastructure.
require 'minitest/autorun'
require 'active_support/core_ext/object/blank'
require 'date'
require 'time'
require 'delegate'
module JrcOperations; end
require_relative '../../app/services/jrc_operations/agenda'

class AgendaSlaPauseTest < Minitest::Test
  Timestamp = Class.new(SimpleDelegator) do
    def in_time_zone(_zone)
      __getobj__
    end
  end
  Record = Struct.new(:id, :status, :title, :metadata, keyword_init: true)

  def setup
    @now = Time.utc(2026, 10, 5, 12)
    @agenda = JrcOperations::Agenda.allocate
    @agenda.instance_variable_set(:@now, @now)
    @agenda.instance_variable_set(:@today, @now.to_date)
    @agenda.instance_variable_set(:@zone, nil)
    context = Object.new
    def context.attributes(_record)
      {}
    end
    @agenda.instance_variable_set(:@customer_context, context)
  end

  def test_paused_crm_projection_stays_open_without_counting_as_overdue
    record = Record.new(id: 7, status: 'scheduled', title: 'Waiting for customer',
                        metadata: { 'relationship_sla_paused_at' => (@now - 7200).iso8601 })
    entry = @agenda.send(:entry, record, kind: 'crm_activity', source: 'crm',
                         due: Timestamp.new(@now - 3600), responsible: nil)
    refute entry[:overdue]
    assert @agenda.send(:matches_view?, entry, 'open')
    refute @agenda.send(:matches_view?, entry, 'overdue')
  end

  def test_resumed_crm_projection_uses_the_rescheduled_deadline
    record = Record.new(id: 7, status: 'scheduled', title: 'Resumed', metadata: {})
    future = @agenda.send(:entry, record, kind: 'crm_activity', source: 'crm',
                          due: Timestamp.new(@now + 3600), responsible: nil)
    refute future[:overdue]
    assert_equal (@now + 3600).iso8601, future[:due]
    late = @agenda.send(:entry, record, kind: 'crm_activity', source: 'crm',
                        due: Timestamp.new(@now - 3600), responsible: nil)
    assert late[:overdue]
    assert @agenda.send(:matches_view?, late, 'overdue')
  end
end
