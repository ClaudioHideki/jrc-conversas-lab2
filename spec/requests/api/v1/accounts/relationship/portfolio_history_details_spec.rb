require 'rails_helper'

RSpec.describe 'Scoped original portfolio history', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: actor)) }
  let(:writer) { JrcRelationship::PortfolioGroups.new(context) }
  let(:group) { JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: 'Synthetic proof') }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship/portfolio_groups/#{group.id}" }
  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  def change
    writer.update!(group.id, attributes: { objective: 'New reviewed value' }, expected_version: group.reload.lock_version,
                   reason: 'Reason frozen with its original sources')
    JrcCrm::AuditEvent.where(resource_type: group.class.name, resource_id: group.id).order(:id).last
  end

  def detail(event)
    get "#{base}/history_detail", headers: actor.create_new_auth_token, params: { event_id: event.id }
  end

  it 'persists a receipt with the original boundary and exposes values only through the exact authorized endpoint' do
    before = group.objective
    event = change
    expect(JrcRelationship::PortfolioHistoryReceipt.where(audit_event_id: event.id).count).to eq(1)
    detail(event)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('available' => true, 'before' => include('objective' => before),
                                            'after' => include('objective' => 'New reviewed value'))
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'captures native distribution rules without projecting explicit local user grants' do
    configuration = JrcRelationship::Configuration.create!(account: account, scope_key: "portfolio:#{group.id}")
    rules = configuration.effective_rules
    event = context.audit!(configuration, action: 'configuration_versioned',
                            before: { version: 1, rules: rules }, after: { version: 2, rules: rules })
    receipt = JrcRelationship::PortfolioHistoryReceipt.find_by!(audit_event_id: event.id)
    expect(receipt.snapshot.fetch('after').fetch('rules').keys).to match_array(JrcRelationship::PortfolioHistoryBoundary::RULE_FIELDS)
    expect(event.reload.to_value.fetch('rules')).to have_key('portfolio_local_access')
    detail(event)
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body).to include('available' => true)
    expect(response.body).not_to include('portfolio_local_access')
  end

  it 'does not synthesize proof for an old audit event' do
    event = JrcCustomers::Audit.record!(account: account, actor: actor, resource: group, event_type: 'relationship_updated',
      metadata: { action: 'portfolio_group_updated' }, from_value: { objective: 'PRIVATE LEGACY' }, to_value: {})
    detail(event)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('available' => false, 'reason' => 'original_scope_unavailable')
    expect(response.body).not_to include('PRIVATE LEGACY')
  end

  it 'keeps the original summary and export free of raw historic values' do
    change
    %w[history export_history].each do |action|
      get "#{base}/#{action}", headers: actor.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('Reason frozen with its original sources', 'New reviewed value')
    end
  end

  it 'refuses another group event even when the actor can see both groups' do
    other = JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: 'Other')
    event = JrcCustomers::Audit.record!(account: account, actor: actor, resource: other, event_type: 'relationship_updated', metadata: {})
    detail(event)
    expect(response).to have_http_status(:not_found)
  end

  it 'denies another account' do
    event = change
    other = create(:user, account: create(:account), role: :administrator)
    get "#{base}/history_detail", headers: other.create_new_auth_token, params: { event_id: event.id }
    expect(response).to have_http_status(:forbidden)
  end

  it 'protects the receipt and the bound audit source against direct SQL updates and deletions' do
    event = change
    receipt = JrcRelationship::PortfolioHistoryReceipt.find_by!(audit_event_id: event.id)
    ["UPDATE jrc_relationship_portfolio_history_receipts SET digest = '#{'0' * 64}' WHERE id = #{receipt.id}",
     "DELETE FROM jrc_relationship_portfolio_history_receipts WHERE id = #{receipt.id}",
     "UPDATE jrc_crm_audit_events SET to_value = '{}' WHERE id = #{event.id}",
     "DELETE FROM jrc_crm_audit_events WHERE id = #{event.id}"].each do |sql|
      expect { ActiveRecord::Base.transaction(requires_new: true) { ActiveRecord::Base.connection.execute(sql) } }
        .to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  it 'rolls back the business change if receipt persistence fails' do
    group
    old = group.objective
    allow(JrcRelationship::PortfolioHistoryReceipt).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
    expect { change }.to raise_error(ActiveRecord::RecordInvalid)
    expect(group.reload.objective).to eq(old)
  end

  it 'does not expose former private scope after sharing the current group' do
    old = create(:user, account: account, role: :agent)
    group.update!(owner: old)
    event = change
    role = create(:custom_role, account: account, permissions: %w[contact_manage jrc_relationship_view jrc_relationship_manage jrc_relationship_team])
    reader = create(:user, account: account, role: :agent)
    account.account_users.find_by!(user: reader).update!(custom_role: role)
    group.reload.update!(owner: reader, visibility: 'account')
    get "#{base}/history_detail", headers: reader.create_new_auth_token, params: { event_id: event.id }
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include('New reviewed value')
  end

  it 'denies proof whose original customer identity changed after the event' do
    assignment = JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account))
    JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: group, assignment: assignment)
    event = change
    assignment.update!(contact: create(:contact, account: account))
    detail(event)
    expect(response).to have_http_status(:forbidden)
  end

  it 'denies direct receipt deletion without deleting the account' do
    event = change
    receipt = JrcRelationship::PortfolioHistoryReceipt.find_by!(audit_event_id: event.id)
    expect { receipt.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect(JrcRelationship::PortfolioHistoryReceipt.exists?(receipt.id)).to be(true)
  end
end
