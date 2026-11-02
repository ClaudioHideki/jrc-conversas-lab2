# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk::PortalGrant do
  include_context 'JRC Service Desk domain'
  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'Synthetic grant organization') }
  let(:contact) { create(:contact, account: sd_account, company_id: company.id) }
  let(:widget) { create(:channel_widget, account: sd_account) }
  let(:identity) { create(:contact_inbox, contact: contact, inbox: widget.inbox, hmac_verified: true) }
  let(:user) { create(:user) }
  let(:attributes) do
    { account: sd_account, company: company, contact: contact, inbox: widget.inbox, contact_inbox: identity,
      user: user, granted_by: sd_user }
  end

  before { sd_as_admin! }

  it 'defaults OFF and never creates or duplicates a native person, operational membership or ticket' do
    attributes
    expect do
      grant = described_class.create!(attributes)
      expect(grant.active?).to be(false)
      expect(grant.expose_sla?).to be(false)
      expect(grant.visible_contact_ids).to eq([])
      expect(grant.available?).to be(false)
    end.not_to(change { [User.count, Contact.count, AccountUser.count, JrcServiceDesk::Ticket.count] })
  end

  it 'requires explicit Account opt-in in addition to an explicit active grant and native SD license' do
    grant = described_class.create!(attributes.merge(active: true))
    expect(grant.available?).to be(false)
    sd_account.update!(internal_attributes: sd_account.internal_attributes.merge('requester_portal_enabled' => true))
    expect(grant.reload.available?).to be(true)
    sd_account.disable_features!('jrc_service_desk')
    expect(grant.reload.available?).to be(false)
  end

  it 'never follows a different company/contact binding and prevents identity mutation' do
    grant = described_class.create!(attributes)
    other_company = JrcCustomers::Company.create!(account: sd_account, name: 'Other synthetic company')
    grant.company = other_company
    expect(grant).not_to be_valid
    expect(grant.errors[:company_id]).not_to be_empty
    grant.reload
    foreign_contact = create(:contact, account: sd_foreign_account)
    grant.contact = foreign_contact
    expect(grant).not_to be_valid
    expect(grant.errors[:contact]).not_to be_empty
  end

  it 'does not infer manager visibility and rejects enumerated contacts in another organization or Account' do
    grant = described_class.new(attributes.merge(role: 'manager'))
    expect(grant.visible_contact_ids).to eq([])
    same_company = create(:contact, account: sd_account, company_id: company.id)
    grant.visible_contact_ids = [same_company.id]
    expect(grant).to be_valid
    different_company = create(:contact, account: sd_account)
    grant.visible_contact_ids = [different_company.id]
    expect(grant).not_to be_valid
    grant.role = 'requester'
    grant.visible_contact_ids = [same_company.id]
    expect(grant).not_to be_valid
  end

  it 'enforces the existing composite identity foreign key even if model validation is bypassed' do
    grant = described_class.create!(attributes)
    foreign_contact = create(:contact, account: sd_foreign_account)
    expect do
      described_class.transaction(requires_new: true) { grant.update_columns(contact_id: foreign_contact.id) }
    end.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it 'denies stale native identity proof after an explicit grant expires or the contact is blocked' do
    sd_account.update!(internal_attributes: sd_account.internal_attributes.merge('requester_portal_enabled' => true))
    grant = described_class.create!(attributes.merge(active: true))
    proof = JrcServiceDesk::PortalSessionProof.new(grant: grant, user: user)
    expect(proof.verify!(identity: identity)).to be(true)
    grant.update!(expires_at: 1.minute.ago)
    expect { proof.verify!(identity: identity) }.to raise_error(JrcServiceDesk::PortalIdentityRequired)
    grant.update!(expires_at: nil)
    contact.update!(blocked: true)
    expect { proof.verify!(identity: identity.reload) }.to raise_error(JrcServiceDesk::PortalIdentityRequired)
  end

  it 'rechecks the current verified identity and company binding instead of following master changes' do
    sd_account.update!(internal_attributes: sd_account.internal_attributes.merge('requester_portal_enabled' => true))
    grant = described_class.create!(attributes.merge(active: true))
    proof = JrcServiceDesk::PortalSessionProof.new(grant: grant, user: user)
    identity.update!(hmac_verified: false)
    expect { proof.verify!(identity: identity.reload) }.to raise_error(JrcServiceDesk::PortalIdentityRequired)
    identity.update!(hmac_verified: true)
    other_company = JrcCustomers::Company.create!(account: sd_account, name: 'Changed master organization')
    contact.update!(company_id: other_company.id)
    expect { proof.verify!(identity: identity.reload) }.to raise_error(JrcServiceDesk::PortalIdentityRequired)
    expect(grant.reload.company_id).to eq(company.id)
  end

  it 'does not retain enumerated manager access when the additional contact changes company' do
    sd_account.update!(internal_attributes: sd_account.internal_attributes.merge('requester_portal_enabled' => true))
    additional = create(:contact, account: sd_account, company_id: company.id)
    additional_identity = create(:contact_inbox, contact: additional, inbox: widget.inbox, hmac_verified: true)
    grant = described_class.create!(attributes.merge(active: true, role: 'manager', visible_contact_ids: [additional.id]))
    proof = JrcServiceDesk::PortalSessionProof.new(grant: grant, user: user, additional_contact: true)
    expect(proof.verify!(identity: additional_identity)).to be(true)
    other_company = JrcCustomers::Company.create!(account: sd_account, name: 'Other manager scope')
    additional.update!(company_id: other_company.id)
    expect { proof.verify!(identity: additional_identity.reload) }.to raise_error(JrcServiceDesk::PortalIdentityRequired)
  end
end
