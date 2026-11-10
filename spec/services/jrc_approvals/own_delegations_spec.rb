require 'rails_helper'

RSpec.describe JrcApprovals::OwnDelegations, :approval_core do
  let(:scope) { approval_scope }
  let(:author) { approval_actor(scope) }
  let(:principal) { approval_actor(scope, permissions: %w[jrc_approvals_decide jrc_approvals_delegate]) }
  let(:recipient) { approval_actor(scope, permissions: ['jrc_approvals_decide']) }
  let(:service) { described_class.new(account: scope[:account], user: principal.user) }
  let(:input) do
    { delegate_id: recipient.id, issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id,
      actions: ['approved'], reason: 'Synthetic own temporary delegation', starts_at: 1.minute.ago, ends_at: 1.hour.from_now,
      idempotency_key: 'synthetic-own-grant' }
  end
  let(:grant) { service.create!(**input) }
  let(:definition) { approval_definition([principal]).merge('delegation_allowed' => true) }
  let(:published) { approval_publish(scope, author, definition) }
  let(:record) do
    published
    approval_request(scope, author)
  end

  it 'records a bounded own grant without policy-management permission or a client-supplied principal' do
    expect(grant.principal_id).to eq(principal.id)
    expect(grant.covers?(scope[:company].id, scope[:unit].id)).to be(true)
    expect(grant.record).to have_attributes(event_type: 'own_delegation_granted', actor_id: principal.id)
    expect { service.create!(**input, principal_id: author.id) }.to raise_error(JrcApprovals::Error, 'INVALID_INPUT')
  end

  it 'works on an old in-flight v1 request and a new policy version without changing either captured plan' do
    old = record
    old_plan = old.stage_plan.deep_dup
    grant
    manager = JrcApprovals::Policies.new(account: scope[:account], user: author.user)
    manager.edit!(policy_id: published.id, expected_version: published.reload.lock_version,
                  name: published.name, definition: definition)
    manager.validate!(policy_id: published.id, expected_version: published.reload.lock_version)
    manager.publish!(policy_id: published.id, expected_version: published.reload.lock_version)
    newer = approval_request(scope, author, key: 'after-new-policy-version')
    [old, newer].each do |request|
      approval_vote(scope, recipient, request, own_delegation_id: grant.id)
      expect(request.reload).to have_attributes(state: 'approved', stage_plan: old_plan)
      expect(request.decisions.first).to have_attributes(actor_id: recipient.id, principal_id: principal.id)
    end
    expect(old.policy_version_id).not_to eq(newer.policy_version_id)
  end

  it 'shows only actual intersected actions and permits bounded technical visibility before any binding write' do
    grant
    request = record
    captured = [JrcApprovals::AuditEvent.count, JrcApprovals::Delegation.count]
    JrcApprovals::RequestVisibility.authorize!(account: scope[:account], user: recipient.user, record: request)
    choices = JrcApprovals::DecisionOptions.call(account: scope[:account], user: recipient.user, record: request)
    expect(choices.first[:choices]).to eq([{ own_delegation_id: grant.id, delegation_id: nil,
                                             principal_name: principal.user.name, actions: ['approved'] }])
    expect([JrcApprovals::AuditEvent.count, JrcApprovals::Delegation.count]).to eq(captured)
    expect(JrcApprovals::Delegation.where(account: scope[:account])).to be_empty
  end

  it 'revokes only an owned grant with append-only history and makes a projected local id unusable' do
    grant
    vote = approval_vote(scope, recipient, record, own_delegation_id: grant.id)
    other = approval_request(scope, author, key: 'second-after-binding')
    bytes = grant.record.attributes.deep_dup
    service.revoke!(id: grant.id)
    expect(grant.record.reload.attributes).to eq(bytes)
    expect(grant.active?).to be(false)
    expect { approval_vote(scope, recipient, other, delegation_id: vote.delegation_id) }
      .to raise_error(JrcApprovals::Error, 'INVALID_DELEGATION')
    expect { JrcApprovals::RequestVisibility.authorize!(account: scope[:account], user: recipient.user, record: other) }
      .to raise_error(Pundit::NotAuthorizedError)
    expect(other.decisions).to be_empty
  end

  it 'denies revocation by another principal without native rule-management authority' do
    grant
    other = approval_actor(scope, permissions: %w[jrc_approvals_delegate jrc_approvals_decide])
    expect { described_class.new(account: scope[:account], user: other.user).revoke!(id: grant.id) }
      .to raise_error(Pundit::NotAuthorizedError)
    expect(grant.active?).to be(true)
  end

  it 'allows an authorized native rule manager to cancel with the actual manager audited' do
    grant
    described_class.new(account: scope[:account], user: author.user).revoke!(id: grant.id)
    expect(grant.active?).to be(false)
    event = JrcApprovals::AuditEvent.find_by!(account_id: scope[:account].id, correlation_key: "own_delegation:revoked:#{grant.id}")
    expect(event.actor_id).to eq(author.id)
  end

  it 'accepts an omitted MVP reason and preserves that fact in the immutable grant and binding' do
    empty_reason = service.create!(**input.except(:reason))
    expect(empty_reason.record.data['reason']).to be_nil
    vote = approval_vote(scope, recipient, record, own_delegation_id: empty_reason.id)
    expect(vote.delegation.reason).to include("Own delegation ##{empty_reason.id}; no reason supplied")
    expect(empty_reason.record.reload.data['reason']).to be_nil
  end

  it 'expires a grant in the resolver without modifying old votes or generating new bindings' do
    grant
    request = record
    travel_to(input[:ends_at] + 1.second) do
      expect { approval_vote(scope, recipient, request, own_delegation_id: grant.id) }
        .to raise_error(JrcApprovals::Error, 'INVALID_DELEGATION')
      expect(JrcApprovals::Delegation.where(account: scope[:account])).to be_empty
    end
  end

  it 'rejects self, reciprocal, mixed scoped/global and overlapping-window cycles' do
    grant
    recipient.custom_role.update!(permissions: recipient.custom_role.permissions + ['jrc_approvals_delegate'])
    expect { service.create!(**input, delegate_id: principal.id, idempotency_key: 'self-own') }
      .to raise_error(JrcApprovals::Error, 'INVALID_DELEGATION')
    expect do
      described_class.new(account: scope[:account], user: recipient.user).create!(**input,
      delegate_id: principal.id, idempotency_key: 'reverse-own')
    end.to raise_error(JrcApprovals::Error, 'INVALID_DELEGATION')
    policy = approval_publish(scope, author, approval_definition([recipient]).merge('delegation_allowed' => true))
    expect do
      JrcApprovals::Delegations.new(account: scope[:account], user: author.user).create!(policy_version_id: policy.current_version_id,
                                                                                         step_code: 'review', principal_id: recipient.id,
                                                                                         delegate_id: principal.id, actions: ['approved'],
                                                                                         reason: 'Synthetic mixed cycle',
                                                                                         starts_at: input[:starts_at], ends_at: input[:ends_at])
    end.to raise_error(JrcApprovals::Error, 'INVALID_DELEGATION')
  end

  it 'does not grant access across tenants or to an inactive or out-of-scope delegate' do
    foreign = approval_scope
    foreign_actor = approval_actor(foreign)
    expect { service.create!(**input, delegate_id: foreign_actor.id) }.to raise_error(ActiveRecord::RecordNotFound)
    grant
    JrcCrm::UserBusinessUnit.where(account_id: scope[:account].id, user_id: recipient.user_id).find_each { |row| row.update!(active: false) }
    expect { approval_vote(scope, recipient, record, own_delegation_id: grant.id) }.to raise_error(Pundit::NotAuthorizedError)
    expect { described_class.find!(foreign[:account], grant.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'rechecks the principal permission and does not allow requester self-approval or duplicate principal votes' do
    grant
    request = record
    approval_vote(scope, recipient, request, own_delegation_id: grant.id)
    expect { approval_vote(scope, principal, request) }.to raise_error(JrcApprovals::Error, 'REQUEST_NOT_PENDING')
    next_request = approval_request(scope, author, key: 'after-principal-revocation')
    principal.custom_role.update!(permissions: ['jrc_approvals_decide'])
    expect { approval_vote(scope, recipient, next_request, own_delegation_id: grant.id) }.to raise_error(Pundit::NotAuthorizedError)
    expect(next_request.decisions).to be_empty
  end

  it 'replays a creation without duplicate grants and rejects a changed intent' do
    first = grant
    expect(service.create!(**input).id).to eq(first.id)
    expect(described_class.grants(scope[:account]).size).to eq(1)
    expect { service.create!(**input, reason: 'Changed intent') }.to raise_error(JrcApprovals::Error, 'IDEMPOTENCY_CONTENT_CONFLICT')
  end

  it 'does not let the original requester approve through an own delegation' do
    self_grant = service.create!(**input, delegate_id: author.id)
    expect { approval_vote(scope, author, record, own_delegation_id: self_grant.id) }.to raise_error(Pundit::NotAuthorizedError)
    expect(record.decisions).to be_empty
  end

  it 'cannot redelegate received authority or add actions that the original grant did not authorize' do
    grant
    recipient.custom_role.update!(permissions: recipient.custom_role.permissions + ['jrc_approvals_delegate'])
    third = approval_actor(scope, permissions: ['jrc_approvals_decide'])
    next_grant = described_class.new(account: scope[:account], user: recipient.user).create!(**input,
      delegate_id: third.id, idempotency_key: 'no-transitive-grant')
    expect { approval_vote(scope, third, record, own_delegation_id: next_grant.id) }.to raise_error(Pundit::NotAuthorizedError)
    expect { approval_vote(scope, recipient, record, own_delegation_id: grant.id, decision: 'rejected') }
      .to raise_error(JrcApprovals::Error, 'INVALID_DELEGATION')
    expect(record.decisions).to be_empty
  end

  it 'denies a rule manager outside the grant issuer/unit even in the same account' do
    other_scope = approval_scope(account: scope[:account])
    other_principal = approval_actor(other_scope)
    other_recipient = approval_actor(other_scope)
    other = described_class.new(account: scope[:account], user: other_principal.user).create!(**input,
      issuer_company_id: other_scope[:company].id, business_unit_id: other_scope[:unit].id,
      delegate_id: other_recipient.id, idempotency_key: 'another-unit-grant')
    expect { described_class.new(account: scope[:account], user: author.user).revoke!(id: other.id) }
      .to raise_error(Pundit::NotAuthorizedError)
    expect(other.active?).to be(true)
  end

  it 'does not count two own delegates as two different principal votes in a quorum' do
    other_principal = approval_actor(scope, permissions: ['jrc_approvals_decide'])
    definition['steps'] = approval_definition([principal, other_principal], mode: 'quorum', quorum: 2)['steps']
    grant
    other_recipient = approval_actor(scope, permissions: ['jrc_approvals_decide'])
    other = service.create!(**input, delegate_id: other_recipient.id, idempotency_key: 'same-principal-second-delegate')
    request = record
    approval_vote(scope, recipient, request, own_delegation_id: grant.id)
    expect(request.reload.state).to eq('pending')
    expect { approval_vote(scope, other_recipient, request, own_delegation_id: other.id) }
      .to raise_error(JrcApprovals::Error, 'ALREADY_VOTED')
    expect(request.decisions.count).to eq(1)
    approval_vote(scope, other_principal, request)
    expect(request.reload.state).to eq('approved')
  end
end
