require 'rails_helper'

RSpec.describe 'Deferred pause current unit and private projection', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:issuer) { account.master_companies.create!(name: 'SYNTHETIC pause issuer', relationship_type: 'internal') }
  let(:business_units) do
    %w[A B].map do |code|
      JrcCrm::BusinessUnit.create!(account: account, operating_company: issuer, code: code, name: "SYNTHETIC pause #{code}")
    end
  end
  let(:units) do
    business_units.map do |unit|
      JrcContactCenter::Unit.create!(account: account, code: unit.code, name: unit.name, kind: 'sac',
                                     settings: { issuer_company_id: issuer.id, business_unit_id: unit.id })
    end
  end
  let(:queues) do
    units.map { |unit| JrcContactCenter::Queue.create!(account: account, unit: unit, code: unit.code, name: unit.name) }
  end
  let(:catalog) { JrcContactCenter::PauseCatalog.new(account: account) }
  let(:manager) { JrcContactCenter::DeferredPauseManager.new(account: account, member: member) }
  let(:values) do
    { command_id: SecureRandom.uuid, reason_code: 'synthetic_private', queue_id: queues.first.id,
      expected_state_version: JrcContactCenter::AgentStateSnapshot.new(account_user: member).version,
      justification: 'SYNTHETIC unit A private explanation',
      expected_request_revision: JrcContactCenter::DeferredPauseRevision.token(account: account, member: member) }
  end
  let(:record) { manager.request!(values) }
  let(:projection) { JrcContactCenter::DeferredPauseProjection.new(account: account, member: member) }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles')
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_operate])
    member.update!(custom_role: role)
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'BUSINESS_UNIT', company: issuer,
                                     business_unit: business_units.first, active: true, structure_managed: true)
    queues.each { |queue| JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member) }
    definition = { 'code' => 'synthetic_private', 'name' => 'SYNTHETIC unit A reason', 'category' => 'SYNTHETIC', 'description' => '',
                   'active' => true, 'minimum_minutes' => 0, 'default_minutes' => 5, 'maximum_minutes' => 10,
                   'unit_ids' => [units.first.id], 'custom_role_ids' => [], 'justification_required' => true }
    catalog.update!({ 'enforced' => true, 'entries' => [definition] }, expected_revision: catalog.revision, activation_confirmed: true)
  end

  include_context 'with a native pending voice ACW for deferred pause'

  it 'uses current corporate scope even when a physical membership exists in another unit' do
    expect do
      manager.request!(values.merge(queue_id: queues.second.id))
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcContactCenter::DeferredPauseRequest.where(account: account)).to be_empty
  end

  it 'recovers private details only for the own request while the original selection is still applicable' do
    expect(projection.call(record)).to include('justification' => values[:justification], 'private_details_available' => true)
    expect(JrcContactCenter::AgentStateSnapshot.new(account_user: member).call.to_json).not_to include(values[:justification])
    expect(Audited::Audit.where(auditable: record).pluck(:audited_changes).to_json).not_to include(values[:justification])
  end

  it 'redacts private historical data after losing the original unit without rewriting the receipt' do
    record
    previous = record.attributes
    JrcCrm::UserBusinessUnit.where(account: account, user: actor).sole.update!(business_unit: business_units.second)
    payload = projection.call(record)
    expect(payload).to include('request_id' => record.request_id, 'private_details_available' => false)
    expect(payload.keys).not_to include('reason_code', 'reason_label', 'queue_id', 'justification')
    expect(record.reload.attributes).to eq(previous)
  end

  it 'rechecks queue eligibility at the eventual transition and remains blocked until explicit review' do
    record
    units.first.update!(status: 'inactive')
    JrcContactCenter::QualificationManager.new(account: account, member: member).complete!(
      pending_pause_qualification, { reason_code: 'order', outcome_code: 'completed', notes: 'SYNTHETIC source completion' }
    )
    expect(record.reload).to have_attributes(state: 'blocked', failure_code: 'queue_membership_missing')
    expect(JrcContactCenter::AgentStateEvent.where(account: account, state: 'paused')).to be_empty
    expect(projection.call(record)).not_to have_key('justification')
    expect(JrcContactCenter::AgentStateSnapshot.new(account_user: member).call[:eligible]).to be(false)
    manager.cancel!(record.request_id)
    expect(record.reload.state).to eq('cancelled')
  end

  it 'refuses a projection from another member even in the same account' do
    record
    other = create(:user, :contact_center_eligible, account: account, role: :agent)
    other_member = account.account_users.find_by!(user: other)
    reader = JrcContactCenter::DeferredPauseProjection.new(account: account, member: other_member)
    expect { reader.call(record) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'does not leak private operational audit metadata through the ordinary account audit list' do
    record
    audit = Audited::Audit.find_by!(auditable: record, comment: JrcContactCenter::DeferredPauseAudit::COMMENT)
    context = { account: account, account_user: member, user: actor }
    rows = JrcContactCenter::ConfigurationAuditScope.protect_native_list(Audited::Audit.where(associated: account), context)
    expect(rows).not_to include(audit)
    expect(Audited::Audit.exists?(audit.id)).to be(true)
    expect(audit.audited_changes).not_to have_key('justification')
  end

  context 'with an independently authorized supervisor' do
    let(:observer) { create(:user, :contact_center_eligible, account: account, role: :agent) }

    before do
      role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_supervise])
      account.account_users.find_by!(user: observer).update!(custom_role: role)
      JrcCrm::UserBusinessUnit.create!(account: account, user: observer, scope: 'BUSINESS_UNIT', company: issuer,
                                       business_unit: business_units.first, active: true, structure_managed: true)
    end

    it 'reports only the scoped operational state, including a blocked request, without sharing the receipt or reason' do
      record
      get "/api/v1/accounts/#{account.id}/jrc_contact_center/supervisor", headers: observer.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('agents').sole.fetch('deferred_pause_notice')).to eq('state' => 'pending')
      expect(response.body).not_to include(record.request_id, record.reason_label, record.justification)
      JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member).update!(eligible: false)
      manager.apply_pending!
      get "/api/v1/accounts/#{account.id}/jrc_contact_center/supervisor", headers: observer.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('agents').sole.fetch('deferred_pause_notice')).to eq('state' => 'blocked')
      expect(response.body).not_to include(record.request_id, record.reason_label, record.justification)
    end

    it 'does not reveal an intent from another unit even if the operator has physical membership in both queues' do
      record
      JrcCrm::UserBusinessUnit.where(account: account, user: observer).sole.update!(business_unit: business_units.second)
      get "/api/v1/accounts/#{account.id}/jrc_contact_center/supervisor", headers: observer.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('agents').sole.fetch('deferred_pause_notice')).to be_nil
      expect(response.body).not_to include(record.request_id, record.reason_label, record.justification)
      expect(record.reload.state).to eq('pending')
    end
  end
end
