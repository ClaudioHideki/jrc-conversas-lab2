require 'rails_helper'

RSpec.describe JrcCustomers::CompanyDocumentsContext do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:company) { account.master_companies.create!(name: 'Canonical document customer') }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, company: company, owner: actor, status: 'active') }
  let(:context) { JrcCustomers::Customer360.new(account: account, user: actor, account_user: member, company: company) }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship') }

  it 'projects the existing authorized assignment and native document capability without copying or creating records' do
    assignment
    result = context.overview
    expect(result.fetch(:capabilities)).to include(relationship: true)
    expect(result.fetch(:document_context)).to include(assignment_id: assignment.id, can_manage_documents: true)
    expect(result.fetch(:document_context).fetch(:formatting)).to eq(JrcRelationship::Context.new(member).formatting)
    expect(JrcRelationship::CustomerDocument.where(account: account)).to be_empty
    expect(JrcRelationship::Assignment.where(account: account).count).to eq(1)
  end

  it 'keeps document management disabled for a native view-only custom role' do
    role = create(:custom_role, account: account,
                                permissions: %w[contact_manage jrc_relationship_view jrc_relationship_documents_view])
    member.update!(role: :agent, custom_role: role)
    assignment
    result = context.overview
    expect(result.fetch(:capabilities)).to include(relationship: true)
    expect(result.fetch(:document_context)).to include(assignment_id: assignment.id, can_manage_documents: false)
  end

  it 'omits the context when the current role has no document permission despite access to the directory and portfolio' do
    role = create(:custom_role, account: account, permissions: %w[contact_manage jrc_relationship_view])
    member.update!(role: :agent, custom_role: role)
    assignment
    result = context.overview
    expect(result.fetch(:document_context)).to be_nil
  end

  it 'does not create a portfolio assignment for a customer that does not have one' do
    result = context.overview
    expect(result.fetch(:document_context)).to be_nil
    expect(JrcRelationship::Assignment.where(account: account)).to be_empty
  end

  it 'does not use another customer assignment as the document context' do
    other = account.master_companies.create!(name: 'Different canonical customer')
    JrcRelationship::Assignment.create!(account: account, company: other, owner: actor, status: 'active')
    expect(context.overview.fetch(:document_context)).to be_nil
  end

  it 'does not use a private portfolio assignment owned by a different agent' do
    member.update!(role: :agent)
    other = create(:user, account: account, role: :agent)
    JrcRelationship::Assignment.create!(account: account, company: company, owner: other, status: 'active')
    expect(context.overview.fetch(:document_context)).to be_nil
  end

  it 'rejects a company from another account before projecting any document context' do
    foreign = create(:account).master_companies.create!(name: 'Foreign company')
    expect do
      JrcCustomers::Customer360.new(account: account, user: actor, account_user: member, company: foreign)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'omits the context after the relationship module is disabled without changing the stored assignment' do
    assignment
    account.disable_features!('jrc_relationship')
    expect(context.overview.fetch(:document_context)).to be_nil
    expect(assignment.reload.company_id).to eq(company.id)
  end
end
