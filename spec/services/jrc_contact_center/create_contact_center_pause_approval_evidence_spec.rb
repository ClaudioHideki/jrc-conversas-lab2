require 'rails_helper'

RSpec.describe 'Additive native pause approval schema', :approval_core do
  include_context 'with all-scope native pause approval'

  def connection
    ApplicationRecord.connection
  end

  # Explicit low-level synthetic fixture, not an approved operational request or a supported API bypass.
  def synthetic_parent
    input = JrcContactCenter::DeferredPauseInput.call(values)
    selection = JrcContactCenter::DeferredPauseSelection.new(account: account, member: member).call(input)
    digest = Digest::SHA256.hexdigest(JrcContactCenter::DeferredPauseInput::FIELDS.map { |key| input[key] }.to_json)
    JrcContactCenter::DeferredPauseRequest.create!(account: account, account_user: member, actor_user_id: actor.id,
      request_id: input.fetch(:command_id), request_digest: digest, state: 'pending', reason_code: input.fetch(:reason_code),
      justification: '', **selection)
  end

  def synthetic_root(parent, intent)
    JrcContactCenter::PauseApprovalReview.create!(account: account, deferred_pause_request_id: parent.id,
      actor_account_user_id: member.id, actor_user_id: actor.id, payload: intent.fetch('payload'), context_digest: intent.fetch('digest'))
  end

  def synthetic_scope(root, group)
    root.scopes.create!(account: account, issuer_company_id: group.fetch('issuer_company_id').to_i,
      business_unit_id: group.fetch('business_unit_id')&.to_i, unit_ids: group.fetch('unit_ids'))
  end

  def check_complete!
    connection.execute('SET CONSTRAINTS cc_pause_approval_review_complete, cc_pause_approval_scope_complete IMMEDIATE')
  end

  it 'rejects committing a source root with no corporate children rather than accepting a merely visual all-unit claim' do
    intent = JrcContactCenter::PauseApprovalIntent.new(context: pause_context).call(values)
    parent = synthetic_parent
    expect do
      JrcContactCenter::PauseApprovalReview.transaction(requires_new: true) do
        synthetic_root(parent, intent)
        check_complete!
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /Pause approval requires every captured scope/)
    expect(JrcContactCenter::PauseApprovalReview.where(account: account)).to be_empty
    expect(parent.reload.state).to eq('pending')
    expect(pause_requests).to be_empty
  end

  it 'rejects a partially inserted corporate set at the database boundary and rolls its scope back with the root' do
    intent = JrcContactCenter::PauseApprovalIntent.new(context: pause_context).call(values)
    parent = synthetic_parent
    expect do
      JrcContactCenter::PauseApprovalReview.transaction(requires_new: true) do
        root = synthetic_root(parent, intent)
        synthetic_scope(root, intent.fetch('payload').fetch('coverage').fetch('groups').first)
        check_complete!
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /Pause approval requires every captured scope/)
    expect(JrcContactCenter::PauseApprovalReview.where(account: account)).to be_empty
    expect(JrcContactCenter::PauseApprovalScope.where(account: account)).to be_empty
    expect(parent.reload.state).to eq('pending')
  end

  it 'accepts a complete immutable source without mistaking source existence for any policy, decision or approval' do
    intent = JrcContactCenter::PauseApprovalIntent.new(context: pause_context).call(values)
    parent = synthetic_parent
    root = nil
    JrcContactCenter::PauseApprovalReview.transaction(requires_new: true) do
      root = synthetic_root(parent, intent)
      intent.fetch('payload').fetch('coverage').fetch('groups').each { |group| synthetic_scope(root, group) }
      check_complete!
    end
    state = JrcContactCenter::PauseApprovalReadiness.new(account: account, member: member).call(parent)
    expect(root.scopes.count).to eq(2)
    expect(state.fetch(:status)).to eq('approval_required')
    expect(state.fetch(:scopes).pluck(:status)).to eq(%w[policy_missing policy_missing])
    expect(pause_requests).to be_empty
    expect(apply_pause(parent).state).to eq('pending')
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
  end

  it 'upgrades a populated native schema without rewriting existing units, memberships or pending pause receipts' do
    require Rails.root.join('db/migrate/20261122120000_create_contact_center_pause_approval_evidence')
    parent = synthetic_parent
    before = [parent.attributes.deep_dup, units.map(&:attributes), JrcContactCenter::QueueMembership.where(account: account).map(&:attributes)]
    expect(JrcContactCenter::PauseApprovalReview.count).to eq(0)
    expect(JrcContactCenter::PauseApprovalScope.count).to eq(0)
    ApplicationRecord.transaction(requires_new: true) do
      connection.execute('DROP TABLE jrc_contact_center_pause_approval_scopes')
      connection.execute('DROP TABLE jrc_contact_center_pause_approval_reviews')
      connection.execute('DROP FUNCTION cc_pause_approval_scope_completeness()')
      connection.execute('DROP FUNCTION cc_pause_approval_evidence_guard()')
      CreateContactCenterPauseApprovalEvidence.new.up
      JrcContactCenter::PauseApprovalReview.reset_column_information
      JrcContactCenter::PauseApprovalScope.reset_column_information
      expect([parent.reload.attributes, units.map { |unit| unit.reload.attributes },
              JrcContactCenter::QueueMembership.where(account: account).map(&:attributes)]).to eq(before)
      expect(JrcContactCenter::PauseApprovalReview.count).to eq(0)
      expect(JrcContactCenter::PauseApprovalScope.count).to eq(0)
      expect { CreateContactCenterPauseApprovalEvidence.new.up }.not_to(change(JrcContactCenter::DeferredPauseRequest, :count))
    end
  end
end
