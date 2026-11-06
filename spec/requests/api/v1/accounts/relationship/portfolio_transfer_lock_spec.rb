require 'rails_helper'

RSpec.describe 'Relationship explicit portfolio transfer restriction', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:target) { create(:user, account: account, role: :administrator) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:headers) { actor.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship" }
  let(:url) { "#{base}/portfolio/#{assignment.id}/transfer_lock" }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  def version
    assignment.reload.updated_at.utc.iso8601(6)
  end

  def restrict(locked: true, reason: 'Synthetic strategic continuity restriction', expected_version: version, **extra)
    patch url, headers: headers, as: :json, params: { restriction: { locked: locked, reason: reason, expected_version: expected_version, **extra } }
  end

  def preview
    post "#{base}/reviewed_batches", headers: headers, as: :json, params: {
      ids: [assignment.id], operation: 'assign', owner_id: target.id, request_id: SecureRandom.uuid
    }
    expect(response).to have_http_status(:ok)
    response.parsed_body
  end

  it 'persists a versioned native restriction and audit using the real actor without moving any responsibility' do
    restrict(actor_id: -1, version: 99, account_id: -1)
    expect(response).to have_http_status(:ok)
    policy = response.parsed_body.fetch('restriction')
    expect(policy).to include('locked' => true, 'version' => 1, 'actor_id' => actor.id, 'changed_at' => a_string_matching(/\A\d{4}-/))
    expect(assignment.reload.owner_id).to eq(actor.id)
    event = JrcCrm::AuditEvent.where(account: account).for_resource(assignment.class.name, assignment.id).last
    expect(event.actor_id).to eq(actor.id)
    expect(event.metadata.fetch('action')).to eq('transfer_lock_changed')
    get "#{base}/portfolio/#{assignment.id}", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('transfer_locked' => true, 'assignment_version' => version)
  end

  it 'requires current configure and team authority rather than team membership alone' do
    role = create(:custom_role, account: account,
                                permissions: %w[contact_manage jrc_relationship_view jrc_relationship_manage jrc_relationship_team])
    actor.account_users.find_by!(account: account).update!(role: :agent, custom_role: role)
    restrict
    expect(response).to have_http_status(:forbidden)
    expect(assignment.reload.settings).not_to have_key('transfer_lock')
  end

  it 'rejects a foreign-account target and never uses supplied account fields to authorize it' do
    foreign = create(:account)
    foreign_user = create(:user, account: foreign)
    row = JrcRelationship::Assignment.create!(account: foreign, owner: foreign_user, contact: create(:contact, account: foreign))
    patch "#{base}/portfolio/#{row.id}/transfer_lock", headers: headers, as: :json, params: { restriction: {
      locked: true, reason: 'Synthetic cross-account attempt', expected_version: row.updated_at.utc.iso8601(6), account_id: foreign.id
    } }
    expect(response).to have_http_status(:not_found)
    expect(row.reload.settings).not_to have_key('transfer_lock')
  end

  it 'respects the current native operating-unit scope even for an administrator' do
    company = account.master_companies.create!(name: 'Synthetic transfer lock operator', relationship_type: 'internal', tax_id: '11444777000161')
    units = Array.new(2) do |index|
      account.jrc_crm_business_units.create!(name: "Synthetic lock unit #{index}", code: SecureRandom.hex(6), company_id: company.id)
    end
    assignment.update!(business_unit: units.last)
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: company,
                                                business_unit: units.first, active: true, structure_managed: true)
    restrict
    expect(response).to have_http_status(:not_found)
    expect(assignment.reload.settings).not_to have_key('transfer_lock')
  end

  it 'revalidates native actor authentication instead of trusting a previously created context' do
    context = JrcRelationship::Context.new(account.account_users.find_by!(user: actor))
    actor.update!(confirmed_at: nil)
    expect do
      JrcRelationship::PortfolioTransferLock.new(context).update!(id: assignment.id, locked: true,
                                                                  reason: 'Synthetic invalid actor', expected_version: version)
    end.to raise_error(Pundit::NotAuthorizedError)
    expect(assignment.reload.settings).not_to have_key('transfer_lock')
  end

  it 'requires explicit boolean state, a bounded reason and current optimistic revision' do
    restrict(locked: 'true')
    expect(response).to have_http_status(:unprocessable_entity)
    restrict(reason: ' ')
    expect(response).to have_http_status(:unprocessable_entity)
    restrict(reason: 'x' * 4001)
    expect(response).to have_http_status(:unprocessable_entity)
    restrict(expected_version: 'old')
    expect(response).to have_http_status(:conflict)
    expect(assignment.reload.settings).not_to have_key('transfer_lock')
  end

  it 'blocks the existing direct owner endpoint without partially moving its work' do
    action = JrcRelationship::Action.create!(account: account, assignment: assignment, owner: actor, kind: 'manual',
                                             reason: 'Synthetic ongoing responsibility', source_key: SecureRandom.uuid)
    restrict
    [target.id, nil].each do |owner_id|
      patch "#{base}/portfolio/#{assignment.id}", headers: headers, as: :json,
                                                  params: { assignment: { owner_id: owner_id, settings: { transfer_lock: { locked: false } } } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(assignment.reload.owner_id).to eq(actor.id)
    expect(action.reload.owner_id).to eq(actor.id)
    expect(assignment.settings.dig('transfer_lock', 'locked')).to be(true)
  end

  it 'rechecks the persisted restriction for a stale ORM instance' do
    stale = JrcRelationship::Assignment.find(assignment.id)
    restrict
    expect { stale.update!(owner: target) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(assignment.reload.owner_id).to eq(actor.id)
  end

  it 'does not allow clearing the restriction and transferring in the same model mutation' do
    restrict
    settings = assignment.reload.settings.deep_dup
    settings['transfer_lock']['locked'] = false
    expect { assignment.update!(owner: target, settings: settings) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(assignment.reload.owner_id).to eq(actor.id)
    expect(assignment.settings.dig('transfer_lock', 'locked')).to be(true)
  end

  it 'blocks a new reviewed preview before persisting an executable proposal' do
    restrict
    expect do
      post "#{base}/reviewed_batches", headers: headers, as: :json, params: {
        ids: [assignment.id], operation: 'assign', owner_id: target.id, request_id: SecureRandom.uuid
      }
    end.not_to change(JrcRelationship::BatchReview, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(assignment.reload.owner_id).to eq(actor.id)
  end

  it 'preserves old review snapshots, invalidates their approval and requires a fresh review after unlocking' do
    old = preview
    review = JrcRelationship::BatchReview.find(old.fetch('id'))
    snapshot = review.snapshot.deep_dup
    restrict
    post "#{base}/reviewed_batches/#{review.id}/approve", headers: headers, as: :json, params: { digest: old.fetch('digest') }
    expect(response).to have_http_status(:unprocessable_entity)
    restrict(locked: false, reason: 'Synthetic authorized release after coverage review')
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('restriction', 'version')).to eq(2)
    expect(review.reload).to have_attributes(snapshot: snapshot, digest: old.fetch('digest'))
    post "#{base}/reviewed_batches/#{review.id}/approve", headers: headers, as: :json, params: { digest: old.fetch('digest') }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'executes a fresh reviewed proposal after the restriction is explicitly released' do
    restrict
    restrict(locked: false, reason: 'Synthetic authorized release after coverage review')
    expect(response).to have_http_status(:ok)
    fresh = preview
    post "#{base}/reviewed_batches/#{fresh.fetch('id')}/approve", headers: headers, as: :json, params: { digest: fresh.fetch('digest') }
    expect(response).to have_http_status(:ok)
    JrcRelationship::BatchExecutionJob.perform_now(fresh.fetch('id'))
    expect(JrcRelationship::BatchReview.find(fresh.fetch('id')).state).to eq('completed')
    expect(assignment.reload.owner_id).to eq(target.id)
  end

  it 'keeps an already-running native batch truthful when a later restriction prevents its work' do
    plan = preview
    post "#{base}/reviewed_batches/#{plan.fetch('id')}/approve", headers: headers, as: :json, params: { digest: plan.fetch('digest') }
    expect(response).to have_http_status(:ok)
    restrict
    JrcRelationship::BatchExecutionJob.perform_now(plan.fetch('id'))
    review = JrcRelationship::BatchReview.find(plan.fetch('id'))
    expect(review.state).to eq('attention')
    expect(review.items.first.state).to eq('failed')
    expect(review.items.first.error_code).to be_present
    expect(assignment.reload.owner_id).to eq(actor.id)
  end

  it 'permits unrelated native work and does not create a new audit for an unchanged restriction' do
    restrict
    before = JrcCrm::AuditEvent.where(account: account).for_resource(assignment.class.name, assignment.id).count
    restrict
    expect(response).to have_http_status(:ok)
    expect(JrcCrm::AuditEvent.where(account: account).for_resource(assignment.class.name, assignment.id).count).to eq(before)
    assignment.update!(status: 'at_risk')
    expect(assignment.reload.settings.dig('transfer_lock', 'locked')).to be(true)
    expect(AccountUser.where(account: account, user: actor)).to exist
  end
end
