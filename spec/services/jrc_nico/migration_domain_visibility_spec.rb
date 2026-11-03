require 'rails_helper'

RSpec.describe 'NICO migration boundaries through native domains' do
  let(:account) { create(:account, custom_attributes: { 'nico_enabled' => true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:access) { JrcNico::OperationalAccess.new(account: account, user: admin).authorize! }
  let(:contact) { create(:contact, account: account, name: 'Pending contact') }

  # Exercise the persisted acceptance contract with both supported target types.
  def pending_mapping(record, domain)
    batch = JrcMigrations::Batch.create!(account: account, created_by: admin, source: 'nico_domain', domain: domain, source_digest: 'a' * 64)
    JrcMigrations::Mapping.create!(account: account, batch: batch, source: 'nico_domain', domain: domain, legacy_id: record.id.to_s,
      target_id: record.id, source_digest: 'a' * 64, target_digest: 'b' * 64, source_updated_at: Time.current)
  end

  before { account.enable_features!('jrc_relationship', 'jrc_customer_master', 'jrc_crm') }

  it 'does not count or project pending contacts in the native conversation radar' do
    pending_mapping(contact, 'contacts')
    hidden = create(:conversation, account: account, contact: contact, status: :open, assignee: nil)
    visible = create(:conversation, account: account, status: :open, assignee: nil)
    result = JrcNico::ConversationRadar.new(access: access, arguments: {}).call
    expect(result[:conversation_ids]).to include(visible.display_id)
    expect(result[:conversation_ids]).not_to include(hidden.display_id)
    expect(result.dig(:categories, 'unassigned', :total)).to eq(1)
  end

  it 'filters CRM records linked to a pending contact before projection' do
    pending_mapping(contact, 'contacts')
    hidden = create(:jrc_crm_lead, account: account, owner: admin, contact: contact)
    visible = create(:jrc_crm_lead, account: account, owner: admin)
    expect(access.crm_scope(JrcCrm::Lead).pluck(:id)).to include(visible.id)
    expect(access.crm_scope(JrcCrm::Lead).pluck(:id)).not_to include(hidden.id)
  end

  it 'does not bypass acceptance when authorizing a saved conversation evidence source' do
    pending_mapping(contact, 'contacts')
    conversation = create(:conversation, account: account, contact: contact)
    expect do
      JrcNico::DomainAccess.authorize_resource!(access, 'Conversation', conversation.id)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'excludes a pending company from portfolio while leaving native companies visible to humans and NICO' do
    company = JrcCustomers::Company.create!(account: account, name: 'Pending company')
    pending_mapping(company, 'companies')
    hidden = JrcRelationship::Assignment.create!(account: account, company: company, owner: admin, status: 'active')
    native = JrcCustomers::Company.create!(account: account, name: 'Native company')
    visible = JrcRelationship::Assignment.create!(account: account, company: native, owner: admin, status: 'active')
    result = JrcNico::DomainActions.new(access).call('list_relationship_portfolio', {})
    expect(result[:customers].pluck(:assignment_id)).to eq([visible.id])
    expect(JrcRelationship::Context.new(access.membership).assignment(hidden.id)).to eq(hidden)
  end

  it 'blocks Customer360 aggregation before a pending linked contact can enter summaries or caches' do
    company = JrcCustomers::Company.create!(account: account, name: 'Native aggregate company')
    contact.update!(company_id: company.id)
    pending_mapping(contact, 'contacts')
    assignment = JrcRelationship::Assignment.create!(account: account, company: company, owner: admin, status: 'active')
    expect(JrcRelationship::WorkContext).not_to receive(:new)
    expect do
      JrcNico::DomainActions.new(access).call('read_relationship_customer', { 'assignment_id' => assignment.id })
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'rechecks a saved assignment after its company acceptance is revoked' do
    company = JrcCustomers::Company.create!(account: account, name: 'Company with revoked acceptance')
    mapping = pending_mapping(company, 'companies')
    mapping.update!(accepted_at: Time.current, accepted_by: admin)
    assignment = JrcRelationship::Assignment.create!(account: account, company: company, owner: admin, status: 'active')
    expect(JrcNico::DomainAccess.authorize_resource!(access, assignment.class.name, assignment.id)).to eq(assignment)
    mapping.update!(accepted_at: nil, accepted_by: nil)
    expect do
      JrcNico::DomainAccess.authorize_resource!(access, assignment.class.name, assignment.id)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end
end
