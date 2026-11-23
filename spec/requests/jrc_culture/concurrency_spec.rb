# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

RSpec.describe 'Concurrent Manual de Cultura confirmations', type: :request do
  include_context 'Manual de Cultura fixtures'
  self.use_transactional_tests = false

  it 'persists one confirmation and event across independent PostgreSQL requests' do
    database = ActiveRecord::Base.connection.current_database
    skip 'Requires the dedicated synthetic Manual de Cultura database' unless Rails.env.test? && database == 'jrc_culture_test'

    version = culture_version
    version.participations.create!(grant: grant)
    id = grant.id
    path = "#{api}/versions/#{version.id}/confirm"
    headers = [employee_headers, employee.user.create_new_auth_token]
    gate = Queue.new
    threads = headers.map do |auth|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          pid = connection.select_value('SELECT pg_backend_pid()')
          gate.pop
          client = ActionDispatch::Integration::Session.new(Rails.application)
          client.post(path, params: { grant_id: id }, headers: auth, as: :json)
          [pid, client.response.status, client.response.parsed_body]
        end
      end
    end
    2.times { gate << true }
    results = Timeout.timeout(30) { threads.map(&:value) }
    expect(results.map(&:first).uniq.size).to eq(2)
    expect(results.map(&:second)).to eq([200, 200])
    expect(results.map { |result| result.last.fetch('confirmed_at') }.uniq.size).to eq(1)
    expect(JrcCulture::Event.where(account: account, action: 'awareness_confirmed').count).to eq(1)
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
    threads&.each(&:join)
  end
end
