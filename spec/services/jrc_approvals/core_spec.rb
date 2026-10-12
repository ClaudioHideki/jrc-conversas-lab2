require 'rails_helper'

RSpec.describe 'Configurable approval core', approval_core: true do
  let(:scope) { approval_scope }
  let(:author) { approval_actor(scope) }
  let(:approver) { approval_actor(scope) }
  let(:definition) { approval_definition([approver]) }
  let(:policy) { approval_publish(scope, author, definition) }
  let(:request) { policy; approval_request(scope, author) }
  let(:manager) { JrcApprovals::Policies.new(account: scope[:account], user: author.user) }

  it 'starts disabled for a new account and has no production catalog adapter' do
    account = create(:account)
    expect(account.feature_enabled?('jrc_approvals')).to be(false)
    expect { JrcApprovals::Catalog.fetch('crm.proposal.pre_send') }.to raise_error(JrcApprovals::Error, 'ADAPTER_NOT_INSTALLED')
    expect { JrcApprovals::Requests.new(account: account, user: author.user).simulate(key: 'synthetic.review', resource_id: scope[:unit].id) }
      .to raise_error(Pundit::NotAuthorizedError)
  end

  it 'requires native resource visibility before capturing any context, even with core management permission' do
    JrcApprovals::Catalog.register(key: 'synthetic.denied', version: 1, model: JrcCrm::BusinessUnit, fields: { 'active' => 'boolean' },
      authorize: ->(_user, _unit) { false }, capture: ->(_unit) { raise 'Forbidden capture was called' })
    expect { JrcApprovals::Requests.new(account: scope[:account], user: author.user)
      .simulate(key: 'synthetic.denied', resource_id: scope[:unit].id) }.to raise_error(Pundit::NotAuthorizedError)
  ensure
    JrcApprovals::Catalog.instance_variable_get(:@entries).delete('synthetic.denied')
  end

  it 'publishes immutable versions and pins existing requests to their original version' do
    old_request = request
    version = policy.current_version
    new_definition = definition.deep_dup
    new_definition['expires_in_seconds'] = 7200
    manager.edit!(policy_id: policy.id, expected_version: policy.reload.lock_version, name: 'Second synthetic version', definition: new_definition)
    manager.validate!(policy_id: policy.id, expected_version: policy.reload.lock_version)
    manager.publish!(policy_id: policy.id, expected_version: policy.reload.lock_version)
    expect(policy.reload.current_version.version).to eq(2)
    expect(version.reload.definition['expires_in_seconds']).to eq(3600)
    expect(old_request.reload.policy_version_id).to eq(version.id)
    expect { version.update!(definition: {}) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { JrcApprovals::PolicyVersion.transaction(requires_new: true) { version.class.where(id: version.id).delete_all } }
      .to raise_error(ActiveRecord::StatementInvalid, /immutable/)
  end

  it 'retires a policy without altering existing requests or allowing absent-policy approval' do
    existing = request
    manager.retire!(policy_id: policy.id, expected_version: policy.reload.lock_version)
    expect(policy.reload.enabled).to be(false)
    expect { approval_request(scope, author) }.to raise_error(JrcApprovals::Error, 'POLICY_REQUIRED')
    approval_vote(scope, approver, existing)
    expect(existing.reload.state).to eq('approved')
  end

  [nil, {}, { 'eval' => 'approve' }, { 'sql' => 'SELECT 1' }].each do |bad|
    it "blocks publication with incomplete/free-form definition #{bad.inspect}" do
      draft = manager.create!(code: SecureRandom.hex(4), name: 'Invalid synthetic draft', module_key: 'synthetic', event_key: 'review',
        issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id, definition: bad || {})
      expect { manager.validate!(policy_id: draft.id, expected_version: draft.lock_version) }.to raise_error(JrcApprovals::Error)
      expect(draft.reload.enabled).to be(false)
      expect(draft.versions.count).to eq(0)
    end
  end

  it 'rejects missing quorum and missing self-approval/delegation choices' do
    entry = JrcApprovals::Catalog.fetch('synthetic.review')
    definition['steps'][0].delete('quorum')
    expect { JrcApprovals::Definition.validate!(definition, entry) }.to raise_error(JrcApprovals::Error)
    definition['steps'][0]['quorum'] = 1
    definition.delete('allow_self_approval')
    expect { JrcApprovals::Definition.validate!(definition, entry) }.to raise_error(JrcApprovals::Error)
  end

  it 'blocks overlapping exclusive priorities but allows an explicitly higher priority' do
    policy
    expect { approval_publish(scope, author, definition) }.to raise_error(JrcApprovals::Error, 'POLICY_SELECTION_CONFLICT')
    higher = approval_publish(scope, author, approval_definition([approver], priority: 11))
    expect(approval_request(scope, author).policy_version_id).to eq(higher.current_version_id)
  end

  it 'accumulates explicitly configured policies atomically and blocks mixing modes' do
    a = approval_publish(scope, author, approval_definition([approver], selection: 'accumulate'))
    b = approval_publish(scope, author, approval_definition([approver], selection: 'accumulate'))
    records = JrcApprovals::Requests.new(account: scope[:account], user: author.user)
      .create!(key: 'synthetic.review', resource_id: scope[:unit].id, idempotency_key: 'batch-key')
    expect(records.map(&:policy_version_id)).to contain_exactly(a.current_version_id, b.current_version_id)
    expect { approval_publish(scope, author, definition) }.to raise_error(JrcApprovals::Error, 'POLICY_SELECTION_CONFLICT')
  end

  it 'simulates without creating requests, votes, audit events or CRM effects' do
    policy
    before = [JrcApprovals::Request.count, JrcApprovals::Decision.count, JrcApprovals::AuditEvent.count, JrcCrm::SalesOrder.count]
    result = JrcApprovals::Requests.new(account: scope[:account], user: author.user).simulate(key: 'synthetic.review', resource_id: scope[:unit].id)
    expect(result[:versions].first[:plan].first['principal_ids']).to eq([approver.id])
    expect(result[:effects]).to eq([])
    expect([JrcApprovals::Request.count, JrcApprovals::Decision.count, JrcApprovals::AuditEvent.count, JrcCrm::SalesOrder.count]).to eq(before)
  end

  it 'rolls back an accumulated batch completely when a later policy loses eligible approvers' do
    second = approval_actor(scope)
    approval_publish(scope, author, approval_definition([approver], selection: 'accumulate'))
    approval_publish(scope, author, approval_definition([second], selection: 'accumulate'))
    second.custom_role.update!(permissions: [])
    expect { approval_request(scope, author) }.to raise_error(JrcApprovals::Error, 'INSUFFICIENT_APPROVERS')
    expect(JrcApprovals::Request.where(account_id: scope[:account].id).count).to eq(0)
    expect(JrcApprovals::AuditEvent.where(account_id: scope[:account].id, event_type: 'request_created').count).to eq(0)
  end

  it 'calculates snapshots and fingerprints on the server and rejects modified request-key content' do
    policy
    first = approval_request(scope, author, key: 'once')
    second = approval_request(scope, author, key: 'once')
    expect(second.id).to eq(first.id)
    expect(first.snapshot.dig('values', 'amount', 'amount_cents')).to eq(2000)
    expect(first.fingerprint).to match(/\A[a-f0-9]{64}\z/)
    scope[:unit].update!(settings: scope[:unit].settings.merge('test_amount' => 2001))
    expect { approval_request(scope, author, key: 'once') }.to raise_error(JrcApprovals::Error, 'IDEMPOTENCY_CONTENT_CONFLICT')
    expect(JrcApprovals::AuditEvent.where(request_id: first.id, event_type: 'request_created').count).to eq(1)
  end

  it 'rejects cross-tenant policy creation, resource selection and decision even for administrators' do
    foreign = approval_scope
    outsider = approval_actor(foreign, role: :administrator)
    expect { JrcApprovals::Policies.new(account: foreign[:account], user: outsider.user)
      .retire!(policy_id: policy.id, expected_version: policy.lock_version) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { JrcApprovals::Requests.new(account: foreign[:account], user: outsider.user)
      .create!(key: 'synthetic.review', resource_id: scope[:unit].id, idempotency_key: 'cross') }.to raise_error(ActiveRecord::RecordNotFound)
    expect { approval_vote(foreign, outsider, request) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'blocks another issuer/unit in the same tenant without explicit coverage' do
    foreign = approval_scope(account: scope[:account])
    expect { manager.create!(code: 'other-company', name: 'Forbidden', module_key: 'synthetic', event_key: 'review',
      issuer_company_id: foreign[:company].id, business_unit_id: foreign[:unit].id, definition: definition) }
      .to raise_error(Pundit::NotAuthorizedError)
    expect { manager.create!(code: 'mixed-company', name: 'Forbidden', module_key: 'synthetic', event_key: 'review',
      issuer_company_id: scope[:company].id, business_unit_id: foreign[:unit].id, definition: definition) }
      .to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'does not promote an undesignated administrator or Backoffice operator to an approver' do
    outsider = approval_actor(scope, role: :administrator)
    expect { approval_vote(scope, outsider, request) }.to raise_error(Pundit::NotAuthorizedError)
    operator = approval_actor(scope, permissions: ['jrc_approvals_request_create'])
    expect { approval_vote(scope, operator, request) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'blocks self-approval unless the policy explicitly permits it' do
    both = approval_definition([author, approver], mode: 'quorum', quorum: 1)
    approval_publish(scope, author, both)
    pending = approval_request(scope, author)
    expect { approval_vote(scope, author, pending) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'allows explicitly configured self-approval and records real identity' do
    definition['allow_self_approval'] = true
    definition['steps'][0]['assignees'] = [{ 'type' => 'account_user', 'id' => author.id }]
    vote = approval_vote(scope, author, request)
    expect(vote.actor_id).to eq(author.id)
    expect(request.reload.state).to eq('approved')
  end

  %w[permissions membership user].each do |kind|
    it "rechecks #{kind} eligibility at decision time" do
      pending = request
      case kind
      when 'permissions' then approver.custom_role.update!(permissions: [])
      when 'membership' then JrcCrm::UserBusinessUnit.where(account_id: scope[:account].id, user_id: approver.user_id).update_all(active: false)
      when 'user' then approver.user.update!(confirmed_at: nil)
      end
      expect { approval_vote(scope, approver, pending) }.to raise_error(Pundit::NotAuthorizedError)
      expect(pending.decisions.count).to eq(0)
    end
  end

  it 'uses explicit quorum and preserves unanimous roster size when a member loses eligibility' do
    second = approval_actor(scope)
    policy = approval_publish(scope, author, approval_definition([approver, second], mode: 'all', quorum: 2))
    pending = approval_request(scope, author)
    approval_vote(scope, approver, pending)
    expect(pending.reload.state).to eq('pending')
    second.custom_role.update!(permissions: [])
    expect { approval_vote(scope, second, pending) }.to raise_error(Pundit::NotAuthorizedError)
    expect(pending.stage_plan.first['quorum']).to eq(2)
    expect(policy.current_version.definition['steps'].first['mode']).to eq('all')
  end

  it 'honors distinct stage assignments and sequential execution' do
    second = approval_actor(scope)
    definition['steps'] << approval_definition([second])['steps'][0].merge('code' => 'second')
    pending = request
    expect { approval_vote(scope, second, pending, step_code: 'second') }.to raise_error(JrcApprovals::Error, 'STEP_NOT_CURRENT')
    approval_vote(scope, approver, pending)
    expect(pending.reload.state).to eq('pending')
    approval_vote(scope, second, pending, step_code: 'second')
    expect(pending.reload.state).to eq('approved')
  end

  it 'allows explicitly parallel stages to be decided out of order' do
    second = approval_actor(scope)
    definition['execution'] = 'parallel'
    definition['steps'] << approval_definition([second])['steps'][0].merge('code' => 'second')
    pending = request
    approval_vote(scope, second, pending, step_code: 'second')
    approval_vote(scope, approver, pending)
    expect(pending.reload.state).to eq('approved')
  end

  it 'resolves native team and custom-role targets without changing their permissions' do
    team = create(:team, account: scope[:account])
    JrcCrm::TeamScope.create!(account: scope[:account], team: team, scope: 'BUSINESS_UNIT', business_unit: scope[:unit], company: scope[:company])
    create(:team_member, team: team, user: approver.user)
    definition['steps'][0]['assignees'] = [{ 'type' => 'team', 'id' => team.id }, { 'type' => 'custom_role', 'id' => approver.custom_role_id }]
    expect(request.stage_plan.first['principal_ids']).to eq([approver.id])
    approval_vote(scope, approver, request)
    expect(request.reload.state).to eq('approved')
  end

  it 'rejects a stage authority outside the explicit bounds without approving by omission' do
    definition['steps'][0]['authority'] = { 'field' => 'amount', 'op' => 'lte', 'value' => { 'amount_cents' => 1000, 'currency' => 'BRL' } }
    policy
    expect { approval_request(scope, author) }.to raise_error(JrcApprovals::Error, 'AUTHORITY_NOT_APPLICABLE')
  end

  it 'blocks a team without native organizational coverage at publication' do
    team = create(:team, account: scope[:account])
    create(:team_member, team: team, user: approver.user)
    definition['steps'][0]['assignees'] = [{ 'type' => 'team', 'id' => team.id }]
    expect { policy }.to raise_error(JrcApprovals::Error, 'TEAM_SCOPE_NOT_AUTHORIZED')
  end

  it 'rejects a current version belonging to another policy in the same tenant at the database boundary' do
    original = policy
    other = approval_publish(scope, author, approval_definition([approver], priority: 11))
    expect { JrcApprovals::Policy.transaction(requires_new: true) {
      original.class.where(id: original.id).update_all(current_version_id: other.current_version_id)
    } }.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(original.reload.current_version.policy_id).to eq(original.id)
  end

  %w[rejected returned escalated].each do |decision|
    it "records individual #{decision} with a mandatory reason and no operational effects" do
      pending = request
      expect { approval_vote(scope, approver, pending, decision: decision, reason: '') }.to raise_error(JrcApprovals::Error, 'REASON_REQUIRED')
      before = [JrcCrm::Proposal.count, JrcCrm::SalesOrder.count, JrcCrm::Contract.count, Message.count]
      approval_vote(scope, approver, pending, decision: decision)
      expect(pending.reload.state).to eq(decision)
      expect([JrcCrm::Proposal.count, JrcCrm::SalesOrder.count, JrcCrm::Contract.count, Message.count]).to eq(before)
    end
  end

  it 'keeps decisions append-only and does not count old votes after explicitly restarting all steps' do
    definition['reopen_mode'] = 'restart_all'
    pending = request
    vote = approval_vote(scope, approver, pending, decision: 'returned')
    reopened = JrcApprovals::Requests.new(account: scope[:account], user: author.user)
      .transition!(request_id: pending.id, action: 'reopen', expected_version: pending.reload.lock_version, reason: 'Synthetic corrected evidence')
    expect(reopened.cycle).to eq(2)
    approval_vote(scope, approver, reopened)
    expect(reopened.reload.state).to eq('approved')
    expect(reopened.decisions.pluck(:cycle)).to contain_exactly(1, 2)
    expect { vote.update!(reason: 'overwrite') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { JrcApprovals::Decision.transaction(requires_new: true) { vote.class.where(id: vote.id).update_all(reason: 'overwrite') } }
      .to raise_error(ActiveRecord::StatementInvalid, /immutable/)
  end

  it 'rejects expiration at the exact deadline and audits explicit expiration' do
    pending = request
    travel_to(pending.expires_at, with_usec: true) do
      expect { approval_vote(scope, approver, pending) }.to raise_error(JrcApprovals::Error, 'REQUEST_EXPIRED')
      JrcApprovals::Requests.new(account: scope[:account], user: author.user)
        .transition!(request_id: pending.id, action: 'expire', expected_version: pending.lock_version, reason: 'Deadline reached')
      expect(pending.reload.state).to eq('expired')
    end
  end

  it 'blocks decisions on canceled or obsolete commercial context and preserves the immutable snapshot' do
    pending = request
    original = pending.snapshot.deep_dup
    scope[:unit].update!(settings: scope[:unit].settings.merge('test_amount' => 999))
    expect { approval_vote(scope, approver, pending) }.to raise_error(JrcApprovals::Error, 'CONTEXT_STALE')
    JrcApprovals::Requests.new(account: scope[:account], user: author.user)
      .transition!(request_id: pending.id, action: 'invalidate', expected_version: pending.lock_version, reason: 'Server amount changed')
    expect(pending.reload.state).to eq('stale')
    expect(pending.snapshot).to eq(original)
    expect { approval_vote(scope, approver, pending) }.to raise_error(JrcApprovals::Error, 'REQUEST_NOT_PENDING')
  end

  it 'cancels without reopening a terminal request' do
    pending = request
    JrcApprovals::Requests.new(account: scope[:account], user: author.user)
      .transition!(request_id: pending.id, action: 'cancel', expected_version: pending.lock_version, reason: 'Requester canceled')
    expect { approval_vote(scope, approver, pending) }.to raise_error(JrcApprovals::Error, 'REQUEST_NOT_PENDING')
    expect { JrcApprovals::Requests.new(account: scope[:account], user: author.user)
      .transition!(request_id: pending.id, action: 'reopen', expected_version: pending.reload.lock_version, reason: 'Retry') }
      .to raise_error(JrcApprovals::Error, 'INVALID_TRANSITION')
  end

  it 'invalidates an approved snapshot after a relevant server-side change without reusing its decision' do
    pending = request
    vote = approval_vote(scope, approver, pending)
    scope[:unit].update!(settings: scope[:unit].settings.merge('test_quantity' => '3.00'))
    JrcApprovals::Requests.new(account: scope[:account], user: author.user)
      .transition!(request_id: pending.id, action: 'invalidate', expected_version: pending.reload.lock_version, reason: 'Quantity changed')
    expect(pending.reload.state).to eq('stale')
    expect(vote.reload.decision).to eq('approved')
    expect(approval_request(scope, author).id).not_to eq(pending.id)
  end

  it 'accepts only identical decision-key replay, with no duplicate vote, version or audit' do
    pending = request
    key = { idempotency_key: 'vote-once', expected_version: 0 }
    first = approval_vote(scope, approver, pending, **key)
    second = approval_vote(scope, approver, pending, **key)
    expect(second.id).to eq(first.id)
    expect(pending.reload.lock_version).to eq(1)
    expect(pending.decisions.count).to eq(1)
    expect(JrcApprovals::AuditEvent.where(decision_id: first.id).count).to eq(1)
    expect { approval_vote(scope, approver, pending, **key, reason: 'Other evidence') }
      .to raise_error(JrcApprovals::Error, 'IDEMPOTENCY_CONTENT_CONFLICT')
    expect { approval_vote(scope, approver, pending, expected_version: 0) }.to raise_error(JrcApprovals::Error, 'VERSION_CONFLICT')
  end

  it 'protects audit and snapshot from bulk SQL and rejects multi-tenant foreign keys' do
    pending = request
    event = JrcApprovals::AuditEvent.find_by!(request_id: pending.id)
    expect { JrcApprovals::AuditEvent.transaction(requires_new: true) { event.class.where(id: event.id).delete_all } }
      .to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    expect { JrcApprovals::Request.transaction(requires_new: true) { pending.class.where(id: pending.id).update_all(snapshot: {}) } }
      .to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    foreign = approval_scope
    foreign_actor = approval_actor(foreign)
    expect { JrcApprovals::Decision.transaction(requires_new: true) {
      JrcApprovals::Decision.create!(account: foreign[:account], request: pending, actor: foreign_actor, principal: foreign_actor,
        step_code: 'review', cycle: 1, decision: 'approved', reason: 'Synthetic cross-tenant SQL attempt',
        expected_version: 0, idempotency_key: 'cross-tenant-db', payload_digest: 'a' * 64)
    } }.to raise_error(ActiveRecord::InvalidForeignKey)
    expect { JrcApprovals::Request.transaction(requires_new: true) {
      pending.class.connection.execute("UPDATE jrc_approvals_requests SET account_id = #{foreign[:account].id} WHERE id = #{pending.id}")
    } }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it 'supports a valid delegation within the same tenant/unit and preserves one principal vote' do
    definition['delegation_allowed'] = true
    pending = request
    delegate = approval_actor(scope)
    grant = JrcApprovals::Delegations.new(account: scope[:account], user: author.user).create!(policy_version_id: pending.policy_version_id,
      step_code: 'review', principal_id: approver.id, delegate_id: delegate.id, actions: ['approved'], reason: 'Synthetic temporary absence',
      starts_at: 1.minute.ago, ends_at: 1.hour.from_now)
    vote = approval_vote(scope, delegate, pending, delegation_id: grant.id)
    expect(vote.principal_id).to eq(approver.id)
    expect(vote.actor_id).to eq(delegate.id)
    expect(pending.reload.state).to eq('approved')
  end

  %w[expired revoked action outside_unit].each do |kind|
    it "rejects #{kind} delegation at decision time" do
      definition['delegation_allowed'] = true
      pending = request
      delegate = approval_actor(scope)
      service = JrcApprovals::Delegations.new(account: scope[:account], user: author.user)
      grant = service.create!(policy_version_id: pending.policy_version_id, step_code: 'review', principal_id: approver.id,
        delegate_id: delegate.id, actions: ['approved'], reason: 'Synthetic absence', starts_at: 1.minute.ago, ends_at: 15.minutes.from_now)
      action = kind == 'action' ? 'rejected' : 'approved'
      service.revoke!(id: grant.id) if kind == 'revoked'
      JrcCrm::UserBusinessUnit.where(user_id: delegate.user_id).update_all(active: false) if kind == 'outside_unit'
      travel_to(kind == 'expired' ? grant.ends_at : Time.current, with_usec: true) do
        expect(pending.expires_at).to be > Time.current
        if kind == 'outside_unit'
          expect { approval_vote(scope, delegate, pending, delegation_id: grant.id, decision: action) }.to raise_error(Pundit::NotAuthorizedError)
        else
          expect { approval_vote(scope, delegate, pending, delegation_id: grant.id, decision: action) }
            .to raise_error(JrcApprovals::Error, 'INVALID_DELEGATION')
        end
      end
      expect(pending.decisions.count).to eq(0)
    end
  end

  it 'does not grant voting rights to a native administrator merely designated in a rule' do
    admin = create(:user, account: scope[:account], role: :administrator)
    member = scope[:account].account_users.find_by!(user: admin)
    JrcCrm::UserBusinessUnit.create!(account: scope[:account], user: admin, company: scope[:company], business_unit: scope[:unit],
      scope: 'BUSINESS_UNIT', structure_managed: true, active: true)
    definition['steps'][0]['assignees'] << { 'type' => 'account_user', 'id' => member.id }
    expect { approval_vote(scope, member, request) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'uses different explicit rules in two tenants without importing a JRC policy' do
    second = approval_scope
    second_author = approval_actor(second)
    a = approval_actor(second)
    b = approval_actor(second)
    approval_publish(second, second_author, approval_definition([a, b], mode: 'quorum', quorum: 2))
    second_request = approval_request(second, second_author)
    approval_vote(second, a, second_request)
    expect(second_request.reload.state).to eq('pending')
    approval_vote(scope, approver, request)
    expect(request.reload.state).to eq('approved')
    expect(second_request.state).to eq('pending')
  end
end
