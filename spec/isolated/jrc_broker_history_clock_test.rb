# Harness of the real importer call with storage/authorization replaced at their
# boundaries. This is not a Rails/PostgreSQL integration test.
require 'digest'
require 'json'

module JrcBroker; end
require_relative '../../app/services/jrc_broker/history_import'

class Message
  def self.transaction
    yield
  end
end

class HistoryClockConversation
  attr_reader :id, :display_id, :inbox_id, :last_activity_at, :status, :assignee_id, :team_id, :updated_at, :callbacks

  def initialize(stamp)
    @id = @display_id = @inbox_id = 1
    @last_activity_at = stamp
    @status = 'resolved'
    @assignee_id = 7
    @team_id = 3
    @updated_at = Time.utc(2026, 1, 1)
    @callbacks = 0
  end

  def update_columns(attributes)
    raise 'unexpected operational mutation' unless attributes.keys == [:last_activity_at]

    @last_activity_at = attributes.fetch(:last_activity_at)
  end

  def lock
    self
  end

  def find_by!(display_id:)
    raise 'wrong conversation' unless display_id == @display_id

    self
  end
end

def check_clock(initial, imported, expected)
  conversation = HistoryClockConversation.new(initial)
  account = Struct.new(:conversations).new(conversation)
  importer = JrcBroker::HistoryImport.allocate
  importer.instance_variable_set(:@authority, Struct.new(:account).new(account))
  importer.define_singleton_method(:validate!) { |_| nil }
  importer.define_singleton_method(:scope!) { |*| Struct.new(:id).new(1) }
  importer.define_singleton_method(:receipt_scope) { |*| {} }
  importer.define_singleton_method(:persist_message) { |*, **| Struct.new(:created_at, :id).new(imported, 9) }
  input = { 'organization_id' => 'synthetic', 'integration_id' => 'synthetic', 'inbox_id' => 1, 'broker_message_id' => 'synthetic' }
  2.times { importer.call(1, input) }
  raise "clock mismatch: #{conversation.last_activity_at} != #{expected}" unless conversation.last_activity_at == expected
  raise 'operational attributes changed' unless [conversation.status, conversation.assignee_id, conversation.team_id, conversation.updated_at, conversation.callbacks] ==
                                               ['resolved', 7, 3, Time.utc(2026, 1, 1), 0]
end

cases = [
  [Time.utc(2026, 1, 1), Time.utc(2026, 1, 3), Time.utc(2026, 1, 3)],
  [Time.utc(2026, 1, 3), Time.utc(2026, 1, 1), Time.utc(2026, 1, 3)],
  [Time.utc(2026, 1, 3), Time.utc(2026, 1, 3), Time.utc(2026, 1, 3)]
]
cases.each { |values| check_clock(*values) }
puts({ harness: 'real_history_import_call', cases: cases.length, rails: false, postgres: false, passed: true }.to_json)
