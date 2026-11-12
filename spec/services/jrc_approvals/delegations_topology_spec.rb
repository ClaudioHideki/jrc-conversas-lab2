require 'rails_helper'

RSpec.describe JrcApprovals::Delegations, :approval_core do
  let(:scope) { approval_scope }
  let(:author) { approval_actor(scope) }
  let(:a) { approval_actor(scope) }
  let(:b) { approval_actor(scope) }
  let(:c) { approval_actor(scope) }
  let(:now) { Time.current }
  let(:definition) { approval_definition([a, b, c]).merge('delegation_allowed' => true) }
  let(:policy) { approval_publish(scope, author, definition) }
  let(:service) { described_class.new(account: scope[:account], user: author.user) }
  let(:terms) do
    { policy_version_id: policy.current_version_id, step_code: 'review', principal_id: a.id, delegate_id: b.id,
      actions: ['approved'], reason: 'Synthetic temporary coverage', starts_at: now, ends_at: now + 2.hours }
  end

  it 'returns the bounded domain error for self-delegation before the existing database constraint' do
    expect { service.create!(**terms, delegate_id: a.id) }.to raise_error(JrcApprovals::Error, 'INVALID_DELEGATION')
    expect(JrcApprovals::Delegation.where(account_id: scope[:account].id)).to be_empty
  end

  it 'refuses reciprocal overlapping grants regardless of action selection' do
    first = service.create!(**terms)
    expect { service.create!(**terms, principal_id: b.id, delegate_id: a.id, actions: ['returned']) }
      .to raise_error(JrcApprovals::Error, 'INVALID_DELEGATION')
    expect(JrcApprovals::Delegation.where(account_id: scope[:account].id).pluck(:id)).to eq([first.id])
  end

  it 'refuses a longer cycle only when all edges share a nonempty time window' do
    service.create!(**terms)
    service.create!(**terms, principal_id: b.id, delegate_id: c.id, starts_at: now + 1.hour, ends_at: now + 3.hours)
    expect { service.create!(**terms, principal_id: c.id, delegate_id: a.id, starts_at: now + 90.minutes) }
      .to raise_error(JrcApprovals::Error, 'INVALID_DELEGATION')
  end

  it 'allows successive coverage windows that merely touch and cannot form a simultaneous cycle' do
    service.create!(**terms)
    service.create!(**terms, principal_id: b.id, delegate_id: c.id, starts_at: now + 1.hour, ends_at: now + 3.hours)
    grant = service.create!(**terms, principal_id: c.id, delegate_id: a.id, starts_at: now + 2.hours, ends_at: now + 4.hours)
    expect(grant).to be_persisted
    expect(JrcApprovals::Delegation.where(account_id: scope[:account].id).count).to eq(3)
  end

  it 'does not use a revoked grant as an active edge and preserves its history' do
    old = service.create!(**terms)
    service.revoke!(id: old.id)
    grant = service.create!(**terms, principal_id: b.id, delegate_id: a.id)
    expect(grant).to be_persisted
    expect(old.reload.revoked_at).to be_present
    expect(JrcApprovals::AuditEvent.where(account_id: scope[:account].id, event_type: 'delegation_granted').count).to eq(2)
  end

  it 'does not combine independent immutable policy versions into an unsupported global delegation graph' do
    service.create!(**terms)
    other = approval_publish(scope, author, definition.deep_merge('selection' => { 'priority' => 20 }))
    grant = service.create!(**terms, policy_version_id: other.current_version_id, principal_id: b.id, delegate_id: a.id)
    expect(grant).to be_persisted
    expect(grant.policy_version_id).not_to eq(policy.current_version_id)
  end

  it 'keeps native manage permissions and cross-account membership checks before topology validation' do
    foreign = approval_actor(approval_scope)
    expect { service.create!(**terms, delegate_id: foreign.id) }.to raise_error(ActiveRecord::RecordNotFound)
    reviewer = approval_actor(scope, permissions: ['jrc_approvals_decide'])
    expect { described_class.new(account: scope[:account], user: reviewer.user).create!(**terms) }
      .to raise_error(Pundit::NotAuthorizedError)
    expect(JrcApprovals::Delegation.where(account_id: scope[:account].id)).to be_empty
  end
end
