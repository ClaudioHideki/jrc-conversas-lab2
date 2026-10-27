# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk::TicketQuery do
  include_context 'JRC Service Desk domain'

  it 'batches the visible page associations rather than querying them once per ticket' do
    tickets = Array.new(5) { sd_ticket }
    association_reads = []
    callback = lambda do |*args|
      sql = ActiveSupport::Notifications::Event.new(*args).payload[:sql]
      association_reads << sql if sql.match?(/FROM "(?:contacts|jrc_service_desk_ticket_statuses|jrc_service_desk_priorities)"/)
    end
    result = nil
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      collection = described_class.new(user_context: sd_context, parameters: { 'per_page' => 5 }).collection
      result = collection[:items].map { |row| [row.id, row.status.name, row.priority.name, row.requester.name] }
      expect(collection[:meta][:total]).to eq(5)
    end
    expect(result.map(&:first)).to match_array(tickets.map(&:id))
    expect(association_reads.length).to be <= 3
  end
end
