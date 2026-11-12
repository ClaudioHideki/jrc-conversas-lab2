require 'rails_helper'

RSpec.describe 'Approved local role restrictions and documents' do
  let(:account) { create(:account) }
  let(:manager) { create(:user, account: account, role: :administrator) }
  let(:analyst) { create(:user, account: account, role: :agent) }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: manager)) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: manager) }
  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  def rules(user, role, grants: [], categories: [])
    { 'enabled' => true, 'roles' => JrcRelationship::LocalRoleRules::DEFAULTS.deep_dup,
      'members' => [{ 'user_id' => user.id, 'role' => role, 'grants' => grants, 'document_categories' => categories }] }
  end

  def install(value)
    JrcRelationship::Configuration.create!(account: account, scope_key: 'account', rules: { 'portfolio_local_access' => value })
  end

  it 'keeps native users and memberships unchanged when configuring a local role' do
    original = account.account_users.find_by!(user: manager).attributes
    install(rules(manager, 'viewer'))
    expect(account.account_users.find_by!(user: manager).attributes).to eq(original)
    fresh = JrcRelationship::Context.new(account.account_users.find_by!(user: manager))
    expect(fresh.policy.access?).to be_truthy
    expect(fresh.policy.manage?).to be_falsey
    expect(fresh.policy.export?).to be_falsey
  end

  it 'does not infer exports or document downloads from the manager label' do
    install(rules(manager, 'manager'))
    expect(context.policy.export?).to be_falsey
    expect(context.policy.documents_download?).to be_falsey
  end

  it 'allows an explicit export only when native rights also allow it' do
    install(rules(manager, 'manager', grants: %w[export_data export_history]))
    expect(context.policy.export?).to be_truthy
    expect(context.policy.export_history?).to be_truthy
  end

  it 'does not grant configuration rights to an analyst with native agent permissions' do
    install(rules(analyst, 'manager'))
    fresh = JrcRelationship::Context.new(account.account_users.find_by!(user: analyst))
    expect(fresh.policy.configure?).to be_falsey
  end

  it 'limits an own role even when the native membership is administrative' do
    own = assignment
    other = JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: analyst)
    install(rules(manager, 'analyst'))
    expect(context.assignments.pluck(:id)).to include(own.id)
    expect(context.assignments.pluck(:id)).not_to include(other.id)
  end

  it 'does not expose group metadata beyond the local own scope' do
    own = JrcRelationship::PortfolioGroup.create!(account: account, owner: manager, name: 'Synthetic own group')
    foreign_scope = JrcRelationship::PortfolioGroup.create!(account: account, owner: analyst, name: 'Synthetic other group', visibility: 'account')
    install(rules(manager, 'analyst'))
    expect(JrcRelationship::PortfolioGroupScope.resolve(context).pluck(:id)).to include(own.id)
    expect(JrcRelationship::PortfolioGroupScope.resolve(context).pluck(:id)).not_to include(foreign_scope.id)
  end

  it 'intersects an active named portfolio restriction with account permissions' do
    row = assignment
    install(rules(manager, 'manager', grants: %w[export_data]))
    group = JrcRelationship::PortfolioGroup.create!(account: account, owner: manager, name: 'Synthetic restricted export')
    JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: group, assignment: row)
    JrcRelationship::Configuration.create!(account: account, scope_key: "portfolio:#{group.id}",
      rules: { 'portfolio_local_access' => rules(manager, 'viewer') })
    expect(JrcRelationship::LocalAccess.assignment_allowed?(context.member, row, 'export_data')).to be(false)
  end

  it 'does not classify old private documents automatically or permit their download' do
    document = JrcRelationship::CustomerDocument.create!(account: account, assignment: assignment, title: 'Synthetic legacy file', category: 'registration')
    expect(document.confidentiality).to be_nil
    expect(JrcRelationship::DocumentAccess.allowed?(context, document, 'download')).to be(false)
  end

  it 'requires category and restricted grants independently of a permitted customer' do
    document = JrcRelationship::CustomerDocument.create!(account: account, assignment: assignment, title: 'Synthetic restricted file',
      category: 'registration', confidentiality: 'restricted')
    install(rules(manager, 'manager', grants: %w[document_view document_download], categories: %w[registration]))
    expect(JrcRelationship::DocumentAccess.allowed?(context, document, 'view')).to be(false)
    expect(JrcRelationship::DocumentAccess.allowed?(context, document, 'download')).to be(false)
  end

  it 'refuses a foreign-account member binding instead of configuring global access' do
    foreign = create(:user, account: create(:account))
    expect { install(rules(foreign, 'manager')) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(JrcRelationship::Configuration.where(account: account)).not_to exist
  end

  it 'rejects operating permissions configured under the Consulta label without changing membership' do
    value = rules(manager, 'viewer')
    value['roles']['viewer']['actions'] << 'work'
    original = account.account_users.find_by!(user: manager).attributes
    expect { install(value) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(account.account_users.find_by!(user: manager).attributes).to eq(original)
    expect(JrcRelationship::Configuration.where(account: account)).not_to exist
  end

  it 'rejects direct eligibility management under the analyst label' do
    value = rules(analyst, 'analyst')
    value['roles']['analyst']['actions'] << 'manage_eligibility'
    expect { install(value) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'keeps a supervisor eligibility request distinct from authority to apply it' do
    value = rules(manager, 'supervisor')
    value['roles']['supervisor']['actions'] << 'manage_eligibility'
    expect { install(value) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'allows explicit read-only export configuration without giving Consulta write access' do
    value = rules(manager, 'viewer', grants: ['export_data'])
    value['roles']['viewer']['actions'] << 'export_data'
    install(value)
    expect(context.policy.export?).to be_truthy
    expect(context.policy.manage?).to be_falsey
    expect(context.policy.configure?).to be_falsey
  end

  it 'rejects an invalid disabled role definition instead of keeping a latent write grant' do
    value = rules(manager, 'viewer')
    value['enabled'] = false
    value['roles']['viewer']['actions'] << 'execute_transfer'
    expect { install(value) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'rejects malformed local rules at the native configuration model' do
    [false, [], 'invalid', { 'enabled' => 'true' }].each do |value|
      expect { install(value) }.to raise_error(ActiveRecord::RecordInvalid)
    end
    expect(JrcRelationship::Configuration.where(account: account)).not_to exist
  end

  it 'does not ignore a false policy persisted outside the validated configuration writer' do
    row = assignment
    install(rules(manager, 'manager'))
    config = JrcRelationship::Configuration.find_by!(account: account, scope_key: 'account')
    # Deliberately malformed synthetic storage proves the direct mutation boundary,
    # independently of normal model validation. No real settings are changed.
    config.update_columns(rules: { 'portfolio_local_access' => false })
    member = account.account_users.find_by!(user: manager)
    expect { JrcRelationship::LocalAccess.assignment_allowed?(member, row, 'work') }.to raise_error(ArgumentError)
  end

  it 'does not ignore a false policy in an active named portfolio during a mutation' do
    row = assignment
    install(rules(manager, 'manager'))
    group = JrcRelationship::PortfolioGroup.create!(account: account, owner: manager, name: 'Synthetic guarded portfolio')
    JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: group, assignment: row)
    config = JrcRelationship::Configuration.create!(account: account, scope_key: "portfolio:#{group.id}",
      rules: { 'portfolio_local_access' => rules(manager, 'manager') })
    config.update_columns(rules: { 'portfolio_local_access' => false })
    member = account.account_users.find_by!(user: manager)
    expect { JrcRelationship::LocalAccess.assignment_allowed?(member, row, 'work') }.to raise_error(ArgumentError)
  end

end
