require 'rails_helper'

RSpec.describe 'Project card read query scaling', type: :request do
  it 'bounds SELECT growth across one, five and twenty-five cards' do
    account = create(:account)
    account.enable_features!('jrc_projects', 'jrc_customer_master')
    admin = create(:user, account: account, role: :administrator)
    headers = admin.create_new_auth_token
    25.times do |index|
      company = JrcCustomers::Company.create!(account: account, name: "Synthetic #{index}")
      JrcProjects::Project.create!(company_id: company.id, account: account, owner: admin, key: "PERF#{index}", name: 'Synthetic', status: 'planned',
                                   visibility: 'members')
    end
    get "/api/v1/accounts/#{account.id}/projects/projects", params: { per_page: 1 }, headers: headers
    measurements = [1, 5, 25].map do |size|
      queries = []
      subscriber = lambda { |*args|
        payload = args.last
        queries << payload[:sql] if payload[:sql].match?(/\ASELECT/i)
      }
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ActiveRecord::Base.uncached do
        ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
          get "/api/v1/accounts/#{account.id}/projects/projects", params: { per_page: size }, headers: headers
        end
      end
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('data').size).to eq(size)
      elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)
      warn "project_read_request cards=#{size} selects=#{queries.size} elapsed_ms=#{elapsed}"
      queries.size
    end
    expect(measurements.max - measurements.min).to be <= 2
  end
end
