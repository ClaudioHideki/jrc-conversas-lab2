require 'rails_helper'

RSpec.describe 'Native Central portfolio distribution', :approval_core, :commercial_approvals, type: :request do
  let(:scope) { approval_scope }
  let(:permissions) do
    JrcApprovals::Authorization::PERMISSIONS + %w[contact_manage jrc_crm jrc_relationship_view jrc_relationship_manage jrc_relationship_team]
  end
  let(:author) { approval_actor(scope, permissions: permissions, role: :administrator) }
  let(:reviewer) { approval_actor(scope, permissions: permissions) }
  let(:destination) { approval_actor(scope, permissions: permissions) }
  let(:team) { create(:team, account: scope[:account]) }
  let(:first) do
    JrcRelationship::Assignment.create!(account: scope[:account], contact: create(:contact, account: scope[:account]), owner: author.user,
                                        team: team, business_unit: scope[:unit])
  end
  let(:second) do
    JrcRelationship::Assignment.create!(account: scope[:account], contact: create(:contact, account: scope[:account]), owner: author.user,
                                        team: team, business_unit: scope[:unit])
  end
  let(:service) { JrcRelationship::ReviewedPortfolioBatch.new(JrcRelationship::Context.new(author)) }
  let(:preview) do
    service.preview('ids' => [first.id, second.id], 'operation' => 'assign', 'owner_id' => destination.user_id,
                    'justification' => 'Synthetic approved workload transfer', 'request_id' => SecureRandom.uuid)
  end
  let(:review) { JrcRelationship::BatchReview.find(preview.fetch('id')) }
  let(:policy) { commercial_policy(scope, author, [reviewer], key: JrcRelationship::DistributionApproval::KEY) }
  let(:approval) do
    policy
    gate = JrcRelationship::DistributionApproval.new(JrcRelationship::Context.new(author))
    gate.request!(review, digest: review.digest, idempotency_key: 'portfolio-native-approval').first
  end
  let(:base) { "/api/v1/accounts/#{scope[:account].id}/relationship" }

  before do
    scope[:account].enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    [author, reviewer, destination].each { |member| TeamMember.create!(team: team, user: member.user) }
    JrcRelationship::Configuration.create!(account: scope[:account], scope_key: "unit:#{scope[:unit].id}",
                                           rules: { portfolio_transfer_approval_required: true, portfolio_review_validity_minutes: 120 })
  end

  it 'freezes the comparison and justification without transferring any customer during preview or request' do
    original = [first.owner_id, second.owner_id]
    expect(preview.fetch('distribution').pluck('from_owner_id')).to eq(original)
    expect(preview.fetch('distribution').pluck('to_owner_id')).to eq([destination.user_id, destination.user_id])
    expect(review.expires_at).to be_within(2.seconds).of(120.minutes.from_now)
    before = review.attributes.deep_dup
    policy
    2.times do
      JrcRelationship::DistributionApproval.new(JrcRelationship::Context.new(author)).request!(
        review, digest: review.digest, idempotency_key: 'portfolio-native-approval'
      )
    end
    expect([first.reload.owner_id, second.reload.owner_id]).to eq(original)
    expect(review.reload.attributes).to eq(before)
    expect(approval.snapshot['values']).to include('customer_count' => 2, 'context_digest' => review.digest,
                                                   'justification' => 'Synthetic approved workload transfer')
  end

  it 'does not treat manual confirmation as a formal approval' do
    policy
    expect { service.approve(review.id, digest: review.digest) }.to raise_error(ArgumentError, /Formal Central approval/)
    expect(review.reload.state).to eq('previewed')
    expect(first.reload.owner_id).to eq(author.user_id)
  end

  it 'executes only after a native vote, preserving snapshots, individual receipts and idempotent execution' do
    approval_vote(scope, reviewer, approval)
    frozen = review.attributes.slice('inputs', 'snapshot', 'digest')
    expect(service.approve(review.id, digest: review.digest).fetch('state')).to eq('running')
    service.advance(review.id, limit: 1)
    expect([first.reload.owner_id, second.reload.owner_id]).to eq([destination.user_id, author.user_id])
    result = service.advance(review.id)
    expect(result.fetch('state')).to eq('completed')
    expect(result.fetch('items').pluck('state')).to eq(%w[applied applied])
    expect([first.reload.owner_id, second.reload.owner_id]).to eq([destination.user_id, destination.user_id])
    expect(review.reload.attributes.slice('inputs', 'snapshot', 'digest')).to eq(frozen)
    expect(service.advance(review.id)).to eq(result)
  end

  it 'refuses votes against a changed original customer' do
    target = approval
    first.update!(settings: { complexity: 'changed after request' })
    expect { approval_vote(scope, reviewer, target) }.to raise_error(JrcApprovals::Error, 'CONTEXT_STALE')
    expect(target.reload.state).to eq('pending')
  end

  it 'revalidates a pending item after approval and does not execute its changed origin' do
    approval_vote(scope, reviewer, approval)
    service.approve(review.id, digest: review.digest)
    second.update!(settings: { complexity: 'changed before execution' })
    result = service.advance(review.id)
    expect(result.fetch('state')).to eq('attention')
    expect(first.reload.owner_id).to eq(author.user_id)
    expect(second.reload.owner_id).to eq(author.user_id)
    expect(result.fetch('items').pluck('state')).to eq(%w[failed canceled])
  end

  it 'does not reuse an old decision after a new version of the selected policy is published' do
    approval_vote(scope, reviewer, approval)
    manager = JrcApprovals::Policies.new(account: scope[:account], user: author.user)
    native = policy.reload
    manager.edit!(policy_id: native.id, expected_version: native.lock_version, name: 'Revised synthetic transfer',
                  definition: native.draft_definition.merge('expires_in_seconds' => 7200))
    manager.validate!(policy_id: native.id, expected_version: native.reload.lock_version)
    manager.publish!(policy_id: native.id, expected_version: native.reload.lock_version)
    expect { service.approve(review.id, digest: review.digest) }.to raise_error(ArgumentError, /Formal Central approval/)
    expect(first.reload.owner_id).to eq(author.user_id)
    gate = JrcRelationship::DistributionApproval.new(JrcRelationship::Context.new(author))
    renewed = gate.request!(review, digest: review.digest, idempotency_key: 'updated-policy-intent').first
    expect(renewed.policy_version_id).not_to eq(approval.policy_version_id)
    approval_vote(scope, reviewer, renewed)
    expect(service.approve(review.id, digest: review.digest).fetch('state')).to eq('running')
  end

  it 'requires a new review after configuration changes and never edits the old snapshot' do
    approval_vote(scope, reviewer, approval)
    before = review.snapshot.deep_dup
    configuration = JrcRelationship::Configuration.find_by!(account: scope[:account], scope_key: "unit:#{scope[:unit].id}")
    configuration.update!(version: 2, rules: configuration.rules.merge('portfolio_review_validity_minutes' => 180))
    expect { service.approve(review.id, digest: review.digest) }.to raise_error(ArgumentError, /policy changed/)
    expect(review.reload.snapshot).to eq(before)
  end

  it 'stops the native worker when destination permission is revoked after approval' do
    approval_vote(scope, reviewer, approval)
    service.approve(review.id, digest: review.digest)
    destination.custom_role.update!(permissions: [])
    JrcRelationship::BatchExecutionJob.perform_now(review.id)
    expect(review.reload.state).to eq('attention')
    expect([first.reload.owner_id, second.reload.owner_id]).to eq([author.user_id, author.user_id])
  end

  it 'blocks direct individual and bulk ownership changes instead of accepting a forged reviewed request ID' do
    patch "#{base}/portfolio/#{first.id}", headers: author.user.create_new_auth_token, as: :json,
                                           params: { assignment: { owner_id: destination.user_id } }
    expect(response).to have_http_status(:unprocessable_entity), response.body
    post "#{base}/portfolio/batch", headers: author.user.create_new_auth_token, as: :json,
                                    params: { ids: [first.id], operation: 'assign', owner_id: destination.user_id,
                                              request_id: 'reviewed:forged' }
    expect(response).to have_http_status(:unprocessable_entity), response.body
    expect(first.reload.owner_id).to eq(author.user_id)
  end

  it 'uses native request idempotency and exposes the authorized source in the Central without moving links' do
    policy
    2.times do
      post "#{base}/reviewed_batches/#{review.id}/request_approval", headers: author.user.create_new_auth_token, as: :json,
                                                                     params: { digest: review.digest, idempotency_key: 'source-native-repeat' }
      expect(response).to have_http_status(:ok), response.body
    end
    expect(JrcApprovals::Request.where(resource_type: review.class.name, resource_id: review.id).count).to eq(1)
    get "#{base}/distribution_approval_origins/#{review.id}", headers: reviewer.user.create_new_auth_token
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body['distribution'].pluck('assignment_id')).to eq([first.id, second.id])
    expect(first.reload.owner_id).to eq(author.user_id)
  end

  it 'does not use a cached configuration to bypass a newly required formal transfer' do
    config = JrcRelationship::Configuration.find_by!(account: scope[:account], scope_key: "unit:#{scope[:unit].id}")
    config.update!(version: 2, rules: config.rules.merge('portfolio_transfer_approval_required' => false))
    cached = JrcRelationship::Context.new(author)
    expect(cached.configuration(first).effective_rules['portfolio_transfer_approval_required']).to be(false)
    config.update!(version: 3, rules: config.rules.merge('portfolio_transfer_approval_required' => true))
    params = ActionController::Parameters.new(ids: [first.id], operation: 'assign', owner_id: destination.user_id, request_id: 'old-cache')
    expect { JrcRelationship::PortfolioBatch.new(cached, params).call }.to raise_error(ArgumentError, /formal Central approval/)
    expect(first.reload.owner_id).to eq(author.user_id)
  end

  it 'requires current origin permissions in addition to Central decision permissions' do
    target = approval
    reviewer.custom_role.update!(permissions: JrcApprovals::Authorization::PERMISSIONS)
    expect { approval_vote(scope, reviewer, target) }.to raise_error(Pundit::NotAuthorizedError)
    get "#{base}/distribution_approval_origins/#{review.id}", headers: reviewer.user.create_new_auth_token
    expect(response).not_to have_http_status(:ok)
  end

  it 'preserves the native self-approval prohibition' do
    target = approval
    expect { approval_vote(scope, author, target) }.to raise_error(Pundit::NotAuthorizedError)
    expect(target.reload.state).to eq('pending')
  end

  it 'does not fall back to manual confirmation when the required Approval Center is disabled' do
    scope[:account].disable_features!('jrc_approvals')
    expect(preview.fetch('approval')).to include(required: true, state: 'unavailable')
    expect { service.approve(review.id, digest: review.digest) }.to raise_error(Pundit::NotAuthorizedError)
    expect(first.reload.owner_id).to eq(author.user_id)
  end

  it 'expires the reviewed proposal without replacing or replaying its native approval' do
    approval_vote(scope, reviewer, approval)
    frozen = approval.reload.attributes.deep_dup
    travel_to(3.hours.from_now) do
      expect { service.approve(review.id, digest: review.digest) }.to raise_error(ArgumentError, /expired/)
    end
    expect(first.reload.owner_id).to eq(author.user_id)
    expect(approval.reload.attributes).to eq(frozen)
  end

  it 'requires every accumulated native approval before execution' do
    commercial_policy(scope, author, [reviewer], key: JrcRelationship::DistributionApproval::KEY, selection: 'accumulate', code: 'transfer-a')
    commercial_policy(scope, author, [reviewer], key: JrcRelationship::DistributionApproval::KEY, selection: 'accumulate', code: 'transfer-b')
    gate = JrcRelationship::DistributionApproval.new(JrcRelationship::Context.new(author))
    votes = gate.request!(review, digest: review.digest, idempotency_key: 'transfer-accumulated')
    expect(votes.size).to eq(2)
    approval_vote(scope, reviewer, votes.first)
    expect { service.approve(review.id, digest: review.digest) }.to raise_error(ArgumentError, /Formal Central approval/)
    approval_vote(scope, reviewer, votes.last)
    expect(service.approve(review.id, digest: review.digest).fetch('state')).to eq('running')
    expect(first.reload.owner_id).to eq(author.user_id)
  end

  it 'never falls back to an old approved request when a newer request for the same policy is pending' do
    approval_vote(scope, reviewer, approval)
    gate = JrcRelationship::DistributionApproval.new(JrcRelationship::Context.new(author))
    renewed = gate.request!(review, digest: review.digest, idempotency_key: 'new-review-of-same-policy').first
    expect(renewed.state).to eq('pending')
    expect { service.approve(review.id, digest: review.digest) }.to raise_error(ArgumentError, /Formal Central approval/)
    expect(first.reload.owner_id).to eq(author.user_id)
  end

  it 'exposes the registered native catalog, exact request origin and immutable transfer facts in the authorized report' do
    target = approval
    prefix = "/api/v1/accounts/#{scope[:account].id}/approvals"
    get "#{prefix}/catalogs", headers: author.user.create_new_auth_token,
                              params: { issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id }
    expect(response.parsed_body).to include(a_hash_including('key' => JrcRelationship::DistributionApproval::KEY))
    get "#{prefix}/resources", headers: author.user.create_new_auth_token, params: { key: JrcRelationship::DistributionApproval::KEY }
    expect(response.parsed_body).to include(a_hash_including('id' => review.id))
    get "#{prefix}/requests/#{target.id}", headers: reviewer.user.create_new_auth_token
    expect(response.parsed_body['origin']).to eq('kind' => 'portfolio_distribution', 'review_id' => review.id)
    get "#{prefix}/requests/#{target.id}/report", headers: author.user.create_new_auth_token
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body['captured_values']).to include('context_digest' => review.digest, 'customer_count' => 2,
                                                               'target_user_id' => destination.user_id)
  end

  it 'denies foreign account references and client-supplied issuer or user grants' do
    review
    foreign = create(:user, account: create(:account), role: :administrator)
    get "#{base}/distribution_approval_origins/#{review.id}", headers: foreign.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    post "#{base}/reviewed_batches/#{review.id}/request_approval", headers: author.user.create_new_auth_token, as: :json,
                                                                   params: { digest: review.digest, idempotency_key: 'forged-context',
                                                                             issuer_company_id: scope[:company].id }
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
