require 'rails_helper'

RSpec.describe 'Controlled reversal of Relationship withdrawal', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:analyst) { create(:user, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: analyst) }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: actor)) }
  let(:headers) { actor.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship" }
  let(:url) { "#{base}/team/#{analyst.id}/restore" }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'restores only eligibility through a new audited decision without reverting historical allocations or the prior event' do
    historical = JrcRelationship::Assignment.create!(account: account, owner: analyst, status: 'inactive',
                                                     contact: create(:contact, account: account))
    review = JrcRelationship::WithdrawalReadiness.new(context).call(analyst.id)
    JrcRelationship::AnalystWithdrawal.new(context).call(analyst.id, reason: 'Synthetic withdrawal before reversal',
                                                                     snapshot_digest: review.fetch(:snapshot_digest))
    event = JrcCrm::AuditEvent.where(account: account).for_resource('AccountUser', member.id).last!
    original_event = event.attributes
    get "#{base}/team/#{analyst.id}/withdrawal_readiness", headers: headers
    post url, headers: headers, as: :json, params: { restoration: {
      reason: 'Synthetic new eligibility decision', expected_version: response.parsed_body['eligibility_version']
    } }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('state' => 'withdrawal_reversed', 'scope' => 'relationship')
    expect(member.reload.jrc_relationship_withdrawn_at).to be_nil
    expect(historical.reload.attributes.slice('owner_id', 'status')).to eq('owner_id' => analyst.id, 'status' => 'inactive')
    expect(event.reload.attributes).to eq(original_event)
    restored = JrcCrm::AuditEvent.where(account: account).for_resource('AccountUser', member.id).order(:id).last!
    expect(restored.to_value).to include('scope' => 'relationship', 'reason' => 'Synthetic new eligibility decision')
    expect(JrcRelationship::Context.new(member).policy.access?).to be(true)
  end

  it 'binds each withdrawal cycle to a monotonic revision even when all timestamps fall in one frozen second' do
    freeze_time do
      first_review = JrcRelationship::WithdrawalReadiness.new(context).call(analyst.id)
      first = JrcRelationship::AnalystWithdrawal.new(context).call(analyst.id, reason: 'Synthetic first cycle',
                                                                               snapshot_digest: first_review.fetch(:snapshot_digest))
      post url, headers: headers, as: :json, params: { restoration: { reason: 'Synthetic controlled reversal',
                                                                      expected_version: first.fetch(:eligibility_version) } }
      expect(response).to have_http_status(:ok)
      post "#{base}/team/#{analyst.id}/withdraw", headers: headers, as: :json,
                                                  params: { withdrawal: { reason: 'Synthetic stale first cycle',
                                                                          snapshot_digest: first_review.fetch(:snapshot_digest) } }
      expect(response).to have_http_status(:conflict)
      second_review = JrcRelationship::WithdrawalReadiness.new(context).call(analyst.id)
      expect(second_review.fetch(:snapshot_digest)).not_to eq(first_review.fetch(:snapshot_digest))
      second = JrcRelationship::AnalystWithdrawal.new(context).call(analyst.id, reason: 'Synthetic second current cycle',
                                                                                snapshot_digest: second_review.fetch(:snapshot_digest))
      expect([first.fetch(:eligibility_version), second.fetch(:eligibility_version)]).to eq([1, 3])
      post "#{base}/team/#{analyst.id}/withdraw", headers: headers, as: :json,
                                                  params: { withdrawal: { reason: 'Synthetic old receipt replay',
                                                                          snapshot_digest: first_review.fetch(:snapshot_digest) } }
      expect(response).to have_http_status(:conflict)
      post "#{base}/team/#{analyst.id}/withdraw", headers: headers, as: :json,
                                                  params: { withdrawal: { reason: 'Synthetic current receipt retry',
                                                                          snapshot_digest: second_review.fetch(:snapshot_digest) } }
      expect(response).to have_http_status(:ok)
    end
  end

  it 'validates reason and typed revision and rejects stale repeated restorations without changing the receipt' do
    review = JrcRelationship::WithdrawalReadiness.new(context).call(analyst.id)
    JrcRelationship::AnalystWithdrawal.new(context).call(analyst.id, reason: 'Synthetic withdrawal', snapshot_digest: review.fetch(:snapshot_digest))
    [nil, '1', {}, -1].each do |version|
      post url, headers: headers, as: :json, params: { restoration: { reason: 'Synthetic malformed revision', expected_version: version } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
    post url, headers: headers, as: :json, params: { restoration: { reason: '', expected_version: 1 } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(member.reload.jrc_relationship_withdrawn_at).to be_present
    post url, headers: headers, as: :json, params: { restoration: { reason: 'Synthetic reviewed restoration', expected_version: 1 } }
    expect do
      post url, headers: headers, as: :json, params: { restoration: { reason: 'Synthetic old restoration retry', expected_version: 1 } }
    end.not_to change(JrcCrm::AuditEvent, :count)
    expect(response).to have_http_status(:conflict)
  end

  it 'preserves the native custom-role restrictions instead of granting access through restoration' do
    review = JrcRelationship::WithdrawalReadiness.new(context).call(analyst.id)
    JrcRelationship::AnalystWithdrawal.new(context).call(analyst.id, reason: 'Synthetic withdrawal', snapshot_digest: review.fetch(:snapshot_digest))
    role = account.custom_roles.create!(name: 'Synthetic directory only', permissions: ['contact_manage'])
    member.update!(custom_role: role)
    post url, headers: headers, as: :json, params: { restoration: { reason: 'Synthetic eligibility only', expected_version: 1 } }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('native_permissions_required')).to be(true)
    expect(member.reload.custom_role_id).to eq(role.id)
    expect(member.jrc_relationship_withdrawn_at).to be_nil
    get "#{base}/metadata", headers: analyst.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
  end

  it 'denies a foreign actor, a reviewer without configure permission and an inactive target' do
    review = JrcRelationship::WithdrawalReadiness.new(context).call(analyst.id)
    JrcRelationship::AnalystWithdrawal.new(context).call(analyst.id, reason: 'Synthetic withdrawal', snapshot_digest: review.fetch(:snapshot_digest))
    foreign = create(:user, account: create(:account), role: :administrator)
    attrs = { restoration: { reason: 'Synthetic forbidden restoration', expected_version: 1, actor_id: actor.id } }
    post url, headers: foreign.create_new_auth_token, as: :json, params: attrs
    expect(response).to have_http_status(:forbidden)
    role = account.custom_roles.create!(name: 'Synthetic supervisor',
                                        permissions: %w[jrc_relationship_view jrc_relationship_manage
                                                        jrc_relationship_team])
    actor.account_users.find_by!(account: account).update!(custom_role: role)
    post url, headers: headers, as: :json, params: attrs
    expect(response).to have_http_status(:forbidden)
    actor.account_users.find_by!(account: account).update!(custom_role: nil)
    analyst.update!(confirmed_at: nil)
    post url, headers: headers, as: :json, params: attrs
    expect(response).to have_http_status(:forbidden)
    expect(member.reload.jrc_relationship_withdrawn_at).to be_present
  end

  it 'preserves a pre-counter withdrawal receipt and permits its explicitly reviewed version-zero reversal' do
    member.update!(jrc_relationship_withdrawn_at: Time.current)
    context.audit!(member, action: 'analyst_withdrawn', after: {
                     scope: 'relationship', reason: 'Synthetic prior-version withdrawal', snapshot_digest: 'a' * 64
                   })
    event = JrcCrm::AuditEvent.where(account: account).for_resource('AccountUser', member.id).order(:id).last!
    original = event.attributes
    expect do
      post "#{base}/team/#{analyst.id}/withdraw", headers: headers, as: :json,
                                                  params: { withdrawal: { reason: 'Synthetic legacy retry', snapshot_digest: 'a' * 64 } }
    end.not_to change(JrcCrm::AuditEvent, :count)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('eligibility_version')).to eq(0)
    post url, headers: headers, as: :json, params: { restoration: { reason: 'Synthetic legacy reversal', expected_version: 0 } }
    expect(response).to have_http_status(:ok)
    expect([member.reload.jrc_relationship_withdrawn_at, member.jrc_relationship_eligibility_version]).to eq([nil, 1])
    expect(event.reload.attributes).to eq(original)
  end

  it 'preserves old proposal snapshots but requires a new reviewed execution after eligibility was reversed' do
    member.update!(role: :administrator)
    allocation = JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account))
    analyst_headers = analyst.create_new_auth_token
    inputs = { ids: [allocation.id], operation: 'assign', owner_id: actor.id, request_id: SecureRandom.uuid }
    post "#{base}/reviewed_batches", headers: analyst_headers, as: :json, params: inputs
    expect(response).to have_http_status(:ok)
    old = response.parsed_body
    proposal = JrcRelationship::BatchReview.find(old.fetch('id'))
    original = proposal.attributes.slice('snapshot', 'digest')
    review = JrcRelationship::WithdrawalReadiness.new(context).call(analyst.id)
    expect(review.fetch(:counts).fetch('reviewed_batches')).to eq(1)
    expect do
      JrcRelationship::AnalystWithdrawal.new(context).call(analyst.id, reason: 'Synthetic still-pending withdrawal',
                                                                      snapshot_digest: review.fetch(:snapshot_digest))
    end.to raise_error(ArgumentError, 'Pending responsibilities require effective native handover before withdrawal')
    expect(member.reload.jrc_relationship_withdrawn_at).to be_nil
    post "#{base}/reviewed_batches/#{proposal.id}/cancel", headers: analyst_headers
    expect(response).to have_http_status(:ok)
    expect(proposal.reload.state).to eq('canceled')
    expect(proposal.attributes.slice('snapshot', 'digest')).to eq(original)
    review = JrcRelationship::WithdrawalReadiness.new(context).call(analyst.id)
    JrcRelationship::AnalystWithdrawal.new(context).call(analyst.id, reason: 'Synthetic operator withdrawal',
                                                                     snapshot_digest: review.fetch(:snapshot_digest))
    post url, headers: headers, as: :json, params: { restoration: { reason: 'Synthetic restored operator', expected_version: 1 } }
    expect(response).to have_http_status(:ok)
    post "#{base}/reviewed_batches/#{proposal.id}/approve", headers: analyst_headers, as: :json, params: { digest: old.fetch('digest') }
    expect([response.status, response.parsed_body['errors']]).to eq([422, ['Review is not available']])
    restored = JrcRelationship::Context.new(member.reload)
    expect { JrcRelationship::BatchReviewPlan.new(restored).validate!(proposal.reload) }
      .to raise_error(JrcRelationship::BatchReviewError, 'Reviewed access changed')
    expect(proposal.reload.attributes.slice('snapshot', 'digest')).to eq(original)
    post "#{base}/reviewed_batches", headers: analyst_headers, as: :json, params: inputs.merge(request_id: SecureRandom.uuid)
    expect(response).to have_http_status(:ok)
    fresh = response.parsed_body
    post "#{base}/reviewed_batches/#{fresh.fetch('id')}/approve", headers: analyst_headers, as: :json, params: { digest: fresh.fetch('digest') }
    expect(response).to have_http_status(:ok)
    JrcRelationship::BatchExecutionJob.perform_now(fresh.fetch('id'))
    expect(JrcRelationship::BatchReview.find(fresh.fetch('id')).state).to eq('completed')
  end
end
