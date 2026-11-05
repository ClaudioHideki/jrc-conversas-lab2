require 'rails_helper'

RSpec.describe 'Native analyst withdrawal readiness at representative scale', type: :request do
  it 'counts one thousand persisted allocations without leaking identities or changing responsibilities' do
    expect(ActiveRecord::Base.connection.select_value('SELECT current_database()')).to eq('jrc_rel_v2_candidate_test')
    account = create(:account)
    account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    actor = create(:user, account: account, role: :administrator)
    analyst = create(:user, account: account, role: :agent)
    setup_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    1_000.times do |index|
      contact = create(:contact, account: account, name: "Synthetic readiness scale #{index}")
      JrcRelationship::Assignment.create!(account: account, owner: analyst, contact: contact)
    end
    setup_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - setup_started
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    get "/api/v1/accounts/#{account.id}/relationship/team/#{analyst.id}/withdrawal_readiness", headers: actor.create_new_auth_token

    request_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body).to include('state' => 'pending_responsibilities', 'final_removal_available' => false)
    expect(response.parsed_body.fetch('counts').fetch('allocations')).to eq(1_000)
    expect(response.body.bytesize).to be < 4_096
    expect(response.body).not_to include('Synthetic readiness scale', 'contact_id', 'assignment_id')
    expect([JrcRelationship::Assignment.where(account: account, owner: analyst).count,
            account.account_users.exists?(user: analyst)]).to eq([1_000, true])
    puts({ synthetic_allocations: 1_000, setup_seconds: setup_seconds.round(3), request_seconds: request_seconds.round(3),
           response_bytes: response.body.bytesize }.to_json)
  end
end
