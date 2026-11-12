require 'rails_helper'
require 'timeout'

RSpec.describe 'Native relationship routing conflict response', type: :request do
  self.use_transactional_tests = false

  it 'returns a safe conflict with no partial writes and persists a normal retry after the competing review releases its lock' do
    expect(ActiveRecord::Base.connection.select_value('SELECT current_database()')).to eq('jrc_rel_v2_candidate_test')
    account = create(:account)
    account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    actor = create(:user, account: account, role: :administrator)
    assignment = JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account))
    headers = actor.create_new_auth_token
    attrs = { record: { assignment_id: assignment.id, reason: 'Synthetic safe routing retry', request_id: SecureRandom.uuid } }
    ready = Queue.new
    release = Queue.new
    worker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        JrcRelationship::Assignment.transaction do
          JrcRelationship::DistributionApproval.lock_configuration!(account.id)
          ready << true
          Timeout.timeout(15) { release.pop }
        end
      end
    end
    Timeout.timeout(10) { ready.pop }
    post "/api/v1/accounts/#{account.id}/relationship/records/actions", headers: headers, params: attrs, as: :json
    expect(response).to have_http_status(:conflict), response.body
    expect([assignment.actions.count, account.jrc_crm_activities.count]).to eq([0, 0])
    expect(assignment.reload.owner_id).to eq(actor.id)
    release << true
    worker.value
    post "/api/v1/accounts/#{account.id}/relationship/records/actions", headers: headers, params: attrs, as: :json
    expect(response).to have_http_status(:created), response.body
    expect([assignment.actions.count, account.jrc_crm_activities.count]).to eq([1, 1])
    expect(response.parsed_body.fetch('owner_id')).to eq(actor.id)
  ensure
    release << true if release
    worker&.join(20)
  end
end
