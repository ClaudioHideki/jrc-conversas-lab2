require 'rails_helper'

RSpec.describe 'Reviewed native master-company allocation HTTP boundary', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/reviewed_batches" }
  let(:companies) { Array.new(2) { |index| account.master_companies.create!(name: "Synthetic master HTTP customer #{index}") } }
  let(:group) { JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: 'Synthetic native master HTTP group') }
  let(:input) do
    { operation: 'master_allocation', ids: companies.map(&:id), portfolio_group_id: group.id,
      expected_version: group.lock_version, justification: 'Explicit native initial allocation review', request_id: SecureRandom.uuid,
      creations: companies.map { |company| { company_id: company.id, owner_id: actor.id } } }
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'previews company subjects and confirms one native job, then saves and reads actual per-company allocation receipts' do
    post url, headers: headers, as: :json, params: input
    expect(response).to have_http_status(:ok)
    review = response.parsed_body
    expect(review.fetch('items').pluck('company_id', 'assignment_id')).to eq(companies.map { |company| [company.id, nil] })
    expect(JrcRelationship::Assignment.where(account: account)).to be_empty
    clear_enqueued_jobs
    post "#{url}/#{review.fetch('id')}/approve", headers: headers, as: :json, params: { digest: review.fetch('digest') }
    expect(enqueued_jobs.count { |row| row[:job] == JrcRelationship::BatchExecutionJob }).to eq(1)
    JrcRelationship::BatchExecutionJob.perform_now(review.fetch('id'))
    get "#{url}/#{review.fetch('id')}", headers: headers
    expect(response.parsed_body).to include('state' => 'completed')
    expect(response.parsed_body.fetch('items').map { |item| item.fetch('receipt').slice('company_id', 'allocation_state') })
      .to eq(companies.map { |company| { 'company_id' => company.id, 'allocation_state' => 'created' } })
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'rejects malformed root audiences and nested actor/account/exception overrides without partial previews or native writes' do
    proposal = input
    forged = proposal.deep_dup
    forged.fetch(:creations).first[:account_id] = create(:account).id
    post url, headers: headers, as: :json, params: forged
    expect(response).to have_http_status(:unprocessable_entity)
    post url, headers: headers, as: :json, params: proposal.merge(ids: [companies.first.id, nil])
    expect(response).to have_http_status(:unprocessable_entity)
    post url, headers: headers, as: :json, params: proposal.merge(active: false)
    expect(response).to have_http_status(:unprocessable_entity)
    expect([JrcRelationship::BatchReview.where(account: account).count, JrcRelationship::Assignment.where(account: account).count]).to eq([0, 0])
  end

  it 'does not disclose or execute another actors saved company audience, even within the same account' do
    post url, headers: headers, as: :json, params: input
    review = response.parsed_body
    other = create(:user, account: account, role: :administrator)
    foreign_headers = other.create_new_auth_token
    get "#{url}/#{review.fetch('id')}", headers: foreign_headers
    expect(response).to have_http_status(:not_found)
    post "#{url}/#{review.fetch('id')}/approve", headers: foreign_headers, as: :json, params: { digest: review.fetch('digest') }
    expect(response).to have_http_status(:not_found)
    expect(JrcRelationship::Assignment.where(account: account)).to be_empty
  end

  it 'keeps operational reasons and eligibility exceptions filtered from HTTP logs while retaining request identity' do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    value = { 'creations' => [{ 'company_id' => 1, 'exception_reason' => 'Synthetic private eligibility decision' }],
              'justification' => 'Synthetic private audience reason', 'request_id' => 'synthetic-master-request' }
    filtered = filter.filter(value)
    expect(filtered.fetch('creations').sole.fetch('exception_reason')).to eq('[FILTERED]')
    expect(filtered).to include('justification' => '[FILTERED]', 'request_id' => 'synthetic-master-request')
  end

  it 'does not reinterpret a master-company audience as allocation IDs when formal owner-transfer approval is requested' do
    post url, headers: headers, as: :json, params: input
    review = response.parsed_body
    requests = JrcApprovals::Request.where(account: account).count
    post "#{url}/#{review.fetch('id')}/request_approval", headers: headers, as: :json,
                                                          params: { digest: review.fetch('digest'), idempotency_key: SecureRandom.uuid }
    expect(response).to have_http_status(:unprocessable_entity)
    expect([JrcApprovals::Request.where(account: account).count, JrcRelationship::Assignment.where(account: account).count]).to eq([requests, 0])
  end
end
