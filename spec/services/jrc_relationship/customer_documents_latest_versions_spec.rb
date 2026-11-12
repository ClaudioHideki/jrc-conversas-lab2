require 'rails_helper'

RSpec.describe JrcRelationship::CustomerDocuments do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:role) do
    create(:custom_role, account: account, permissions: %w[contact_manage jrc_relationship_view jrc_relationship_documents_view])
  end
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:document) do
    JrcRelationship::CustomerDocument.create!(account: account, assignment: assignment, title: 'Synthetic selector', category: 'evidence', confidentiality: 'operational')
  end
  let(:context) { JrcRelationship::Context.new(member) }

  before do
    account.enable_features!('jrc_customer_master', 'jrc_relationship')
    member.update!(custom_role: role)
  end

  it 'selects the highest native number only for currently authorized requested documents across private portfolios and accounts' do
    # Selector fixtures need no bytes: this tests authorization and version choice, not upload/scanner behavior.
    document.versions.create!(account: account, uploaded_by: actor, number: 3, change_reason: 'Higher immutable version')
    document.versions.create!(account: account, uploaded_by: actor, number: 1, change_reason: 'Older number inserted later')
    other = create(:user, account: account, role: :agent)
    hidden_assignment = JrcRelationship::Assignment.create!(account: account, owner: other, contact: create(:contact, account: account))
    hidden = JrcRelationship::CustomerDocument.create!(account: account, assignment: hidden_assignment, title: 'Hidden', category: 'evidence', confidentiality: 'operational')
    hidden.versions.create!(account: account, uploaded_by: other, number: 10, change_reason: 'Private portfolio version')
    foreign_account = create(:account)
    foreign_actor = create(:user, account: foreign_account)
    foreign_assignment = JrcRelationship::Assignment.create!(account: foreign_account, owner: foreign_actor,
                                                             contact: create(:contact, account: foreign_account))
    foreign = JrcRelationship::CustomerDocument.create!(account: foreign_account, assignment: foreign_assignment, title: 'Foreign',
                                                        category: 'evidence', confidentiality: 'operational')
    foreign.versions.create!(account: foreign_account, uploaded_by: foreign_actor, number: 20, change_reason: 'Foreign immutable version')
    result = described_class.new(context).latest_versions(document_ids: [document.id, hidden.id, foreign.id])
    expect(result.keys).to eq([document.id])
    expect(result.fetch(document.id)).to have_attributes(number: 3, account_id: account.id, document_id: document.id)
    expect(described_class.new(context).latest_versions(document_ids: [hidden.id, foreign.id])).to eq({})
  end

  it 'keeps empty pages empty but still requires the explicit current native document permission' do
    expect(described_class.new(context).latest_versions(document_ids: [])).to eq({})
    role.update!(permissions: %w[contact_manage jrc_relationship_view])
    current = JrcRelationship::Context.new(member.reload)
    expect { described_class.new(current).latest_versions(document_ids: []) }.to raise_error(Pundit::NotAuthorizedError)
  end
end
