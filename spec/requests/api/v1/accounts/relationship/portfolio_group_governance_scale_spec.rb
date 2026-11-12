require 'rails_helper'

RSpec.describe 'Named portfolio configured batch scale', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:target) { create(:user, account: account, role: :agent) }
  let(:headers) { actor.create_new_auth_token }
  let(:group) { JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: 'Synthetic configured scale portfolio') }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'reviews fifty allocations from one thousand real grouped customers with bounded portfolio queries and no ownership changes' do
    contacts = Contact.create!(Array.new(1000) { |index| { account: account, name: "Synthetic governed scale customer #{index}" } })
    allocations = JrcRelationship::Assignment.create!(contacts.map do |contact|
      { account: account, owner: actor, contact: contact, status: 'active' }
    end)
    JrcRelationship::PortfolioGroupAssignment.create!(allocations.map do |row|
      { account: account, portfolio_group: group, assignment: row, active: true }
    end)
    JrcRelationship::Configuration.create!(account: account, scope_key: "portfolio:#{group.id}", rules: { portfolio_capacity_limits: [
                                             { user_id: actor.id, maximum: 1000, availability: 1, dedication: 1 },
                                             { user_id: target.id, maximum: 50, availability: 1, dedication: 1 }
                                           ] })
    total = 0
    portfolio_queries = 0
    listener = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:name] == 'SCHEMA'

      total += 1
      portfolio_queries += 1 if payload.fetch(:sql).include?('jrc_relationship_portfolio_group')
    end
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    ActiveSupport::Notifications.subscribed(listener, 'sql.active_record') do
      post "/api/v1/accounts/#{account.id}/relationship/reviewed_batches", headers: headers, as: :json,
                                                                           params: { ids: allocations.first(50).map(&:id), operation: 'assign',
                                                                                     owner_id: target.id, request_id: SecureRandom.uuid }
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('capacity')).to include(include('scope_key' => "portfolio:#{group.id}", 'current' => 0,
                                                                      'incoming' => 50, 'projected' => 50, 'blocker' => nil))
    expect(response.parsed_body.fetch('items').size).to eq(50)
    expect(portfolio_queries).to be < 40
    expect(JrcRelationship::Assignment.where(account: account, owner: actor).count).to eq(1000)
    expect(group.customer_links.where(active: true).count).to eq(1000)
    expect(JrcRelationship::BatchReview.find(response.parsed_body.fetch('id')).snapshot.fetch('version')).to eq(1)
    puts({ named_portfolio_configured_scale: { customers: 1000, selected: 50, total_queries: total,
                                               portfolio_queries: portfolio_queries, elapsed_seconds: elapsed.round(4),
                                               real_database: true } }.to_json)
  end
end
