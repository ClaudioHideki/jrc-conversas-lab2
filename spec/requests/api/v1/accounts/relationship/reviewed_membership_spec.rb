require 'rails_helper'

RSpec.describe 'Native reviewed portfolio membership HTTP boundary', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/reviewed_batches" }
  let(:allocation) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:group) { JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: 'Synthetic HTTP portfolio') }
  let(:input) do
    { operation: 'portfolio_membership', ids: [allocation.id], portfolio_group_id: group.id,
      expected_version: group.lock_version, active: true, justification: 'Explicit native reviewed link', request_id: SecureRandom.uuid }
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'uses the existing native HTTP review, confirmation, finite advance and saved readback endpoints' do
    post url, headers: headers, as: :json, params: input
    expect(response).to have_http_status(:ok)
    review = response.parsed_body
    expect(group.customer_links).not_to exist
    post "#{url}/#{review.fetch('id')}/approve", headers: headers, as: :json, params: { digest: review.fetch('digest') }
    expect(response).to have_http_status(:ok)
    post "#{url}/#{review.fetch('id')}/advance", headers: headers, as: :json, params: {}
    expect(response.parsed_body.fetch('items').first.fetch('receipt')).to include('membership_state' => 'linked', 'portfolio_group_id' => group.id)
    get "#{url}/#{review.fetch('id')}", headers: headers
    expect(response.parsed_body.fetch('state')).to eq('completed')
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(group.customer_links.where(active: true).pluck(:assignment_id)).to eq([allocation.id])
  end

  it 'does not reduce a malformed JSON audience, accept a root collection or create partial reviewed work' do
    before = JrcRelationship::BatchReview.count
    post url, headers: headers, as: :json, params: input.merge(ids: [allocation.id, nil])
    expect(response).to have_http_status(:unprocessable_entity)
    post url, headers: headers, as: :json, params: [input]
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcRelationship::BatchReview.count).to eq(before)
    expect(group.customer_links).not_to exist
  end

  it 'retains native tenant and configure-independent group management bounds without accepting identity overrides' do
    foreign = create(:account)
    owner = create(:user, account: foreign, role: :administrator)
    other_group = JrcRelationship::PortfolioGroup.create!(account: foreign, owner: owner, name: 'Foreign group')
    post url, headers: headers, as: :json, params: input.merge(portfolio_group_id: other_group.id)
    expect(response).to have_http_status(:not_found)
    post url, headers: headers, as: :json, params: input.merge(account_id: foreign.id, user_id: owner.id)
    expect(response).to have_http_status(:unprocessable_entity)
    account.account_users.find_by!(user: actor).update!(role: :agent)
    post url, headers: headers, as: :json, params: input
    expect(response).to have_http_status(:not_found)
    expect(group.customer_links).not_to exist
  end

  it 'preserves existing reviewed transfer HTTP input while rejecting null audience entries without partial normalization' do
    proposal = { operation: 'assign', ids: [allocation.id.to_s], owner_id: actor.id, request_id: SecureRandom.uuid }
    post url, headers: headers, as: :json, params: proposal
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('inputs')).to include('operation' => 'assign', 'ids' => [allocation.id], 'owner_id' => actor.id)
    before = JrcRelationship::BatchReview.count
    post url, headers: headers, as: :json, params: proposal.merge(ids: [allocation.id, nil], request_id: SecureRandom.uuid)
    expect(response).to have_http_status(:unprocessable_entity)
    expect([JrcRelationship::BatchReview.count, allocation.reload.owner_id]).to eq([before, actor.id])
  end

  it 'filters free-text justifications from native request logs while retaining operational request identity' do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    expect(filter.filter({ 'justification' => 'Synthetic private reason', 'reason' => 'Synthetic private review', 'request_id' => 'synthetic-id' }))
      .to eq('justification' => '[FILTERED]', 'reason' => '[FILTERED]', 'request_id' => 'synthetic-id')
  end

  it 'retains empty JSON-body compatibility on the existing finite advance action' do
    context = JrcRelationship::Context.new(account.account_users.find_by!(user: actor))
    review = JrcRelationship::ReviewedPortfolioBatch.new(context).preview(input.stringify_keys)
    post "#{url}/#{review.fetch('id')}/approve", headers: headers, as: :json, params: { digest: review.fetch('digest') }
    expect(response).to have_http_status(:ok)
    post "#{url}/#{review.fetch('id')}/advance", headers: headers.merge('CONTENT_TYPE' => 'application/json'), params: ''
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('state')).to eq('completed')
  end
end
