require 'rails_helper'

RSpec.describe 'Reviewed relationship batches', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:row) { JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: admin) }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship/reviewed_batches" }
  let(:input) { { ids: [row.id], operation: 'assign', owner_id: nil, request_id: SecureRandom.uuid } }
  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'requires an explicit frozen review before scheduling native work and keeps receipts visible after completion' do
    post base, params: input, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    preview = response.parsed_body
    expect(row.reload.owner_id).to eq(admin.id)
    clear_enqueued_jobs
    post "#{base}/#{preview.fetch('id')}/approve", params: { digest: preview.fetch('digest') }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(enqueued_jobs.map { |job| job[:job] }).to include(JrcRelationship::BatchExecutionJob)
    JrcRelationship::BatchExecutionJob.perform_now(preview.fetch('id'))
    get "#{base}/#{preview.fetch('id')}", headers: headers, as: :json
    expect(response.parsed_body).to include('state' => 'completed')
    expect(row.reload.owner_id).to be_nil
  end

  it 'does not approve a changed request body or return another accounts batch' do
    post base, params: input, headers: headers, as: :json
    preview = response.parsed_body
    post "#{base}/#{preview.fetch('id')}/approve", params: { digest: preview.fetch('digest'), owner_id: admin.id }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    other = create(:user, account: create(:account), role: :administrator)
    get "#{base}/#{preview.fetch('id')}", headers: other.create_new_auth_token, as: :json
    expect(response).not_to have_http_status(:ok)
  end

  it 'stops queued native work when its authorizing account membership is revoked' do
    post base, params: input, headers: headers, as: :json
    preview = response.parsed_body
    post "#{base}/#{preview.fetch('id')}/approve", params: { digest: preview.fetch('digest') }, headers: headers, as: :json
    admin.account_users.find_by!(account: account).destroy!
    JrcRelationship::BatchExecutionJob.perform_now(preview.fetch('id'))
    record = JrcRelationship::BatchReview.find(preview.fetch('id'))
    expect([record.state, record.items.pluck(:state)]).to eq(['attention', ['canceled']])
    expect(row.reload.owner_id).to eq(admin.id)
  end

  it 'reviews a native cadence, exposes its pinned schedule, and cancels it through account-scoped endpoints' do
    book = JrcRelationship::Playbook.create!(account: account, name: 'Native cadence', active: true, trigger_kind: 'no_contact',
                                            steps: [{ 'kind' => 'activity', 'title' => 'Future task', 'after_days' => 1 }])
    conversation = create(:conversation, account: account, inbox: create(:inbox, account: account), contact: row.contact)
    params = input.merge(operation: 'cadence', playbook_id: book.id, conversation_id: conversation.display_id,
                         starts_at: Time.current.iso8601(6))
    post base, params: params, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    preview = response.parsed_body
    expect(preview.fetch('summary')).to include('contact_name' => row.contact.name, 'conversation_number' => conversation.display_id)
    expect(preview.fetch('summary').fetch('schedule').first.fetch('title')).to eq('Future task')
    post "#{base}/#{preview.fetch('id')}/approve", params: { digest: preview.fetch('digest') }, headers: headers, as: :json
    JrcRelationship::BatchExecutionJob.perform_now(preview.fetch('id'))
    record = JrcRelationship::CadenceEnrollment.find_by!(account: account)
    path = "/api/v1/accounts/#{account.id}/relationship/cadences/#{record.id}"
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('no-store')
    post "#{path}/cancel", params: {}, headers: headers, as: :json
    expect(response.parsed_body).to include('state' => 'stopped', 'stop_reason' => 'CANCELED_BY_OPERATOR')
    expect(JrcCrm::Activity.where(account: account)).to be_empty
  end
end
