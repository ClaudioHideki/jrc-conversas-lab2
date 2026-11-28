# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcCrm::Activity, :pabx do
  context 'when validating native Relationship identity compatibility' do
    include_context 'with native recording Relationship intake'

    let(:direct_portfolio) do
      JrcRelationship::Assignment.create!(account: account, contact: caller_contact, owner: actor, business_unit: business, status: 'active')
    end
    let(:native_activity) do
      described_class.new(account: account, contact: caller_contact, user: actor, activity_type: 'call',
                          title: 'SYNTHETIC native linked identity', due_at: Time.current,
                          metadata: { 'relationship_assignment_id' => direct_portfolio.id })
    end

    it 'accepts the exact contact and company inferred by the native master-link callback without changing the portfolio XOR' do
      native_activity.save!
      expect(native_activity.reload).to have_attributes(contact_id: caller_contact.id, company_id: customer.id)
      expect(direct_portfolio.reload).to have_attributes(contact_id: caller_contact.id, company_id: nil)
    end

    it 'preserves a persisted contact-only historical activity after the contact joins a company' do
      person = create(:contact, account: account)
      portfolio = JrcRelationship::Assignment.create!(account: account, contact: person, owner: actor, status: 'active')
      activity = described_class.create!(account: account, contact: person, user: actor, activity_type: 'call',
                                         title: 'SYNTHETIC historical call', due_at: Time.current,
                                         metadata: { 'relationship_assignment_id' => portfolio.id })
      person.update!(company: customer)
      activity.reload.update!(title: 'SYNTHETIC reviewed historical call')
      expect(activity.reload).to have_attributes(contact_id: person.id, company_id: nil)
      expect(portfolio.reload.company_id).to be_nil
    end

    it 'rejects a different contact even when that contact belongs to the same current company' do
      native_activity.contact = create(:contact, account: account, company: customer)
      expect(native_activity).not_to be_valid
      expect(native_activity.errors[:base]).to include('Relationship identity mismatch')
    end

    it 'rejects an unrelated company instead of broadening contact portfolio identity' do
      native_activity.company = account.master_companies.create!(name: 'SYNTHETIC unrelated company')
      expect(native_activity).not_to be_valid
      expect(native_activity.errors[:base]).to include('Relationship identity mismatch')
    end

    it 'rejects an arbitrary contact on a company portfolio that originally has no contact' do
      native_activity.metadata = { 'relationship_assignment_id' => assignment.id }
      expect(native_activity).not_to be_valid
      expect(native_activity.errors[:base]).to include('Relationship identity mismatch')
    end

    it 'rejects foreign account portfolio metadata even for an otherwise valid same-account contact' do
      other = create(:account)
      foreign = JrcRelationship::Assignment.create!(account: other, contact: create(:contact, account: other), status: 'active')
      native_activity.metadata = { 'relationship_assignment_id' => foreign.id }
      expect(native_activity).not_to be_valid
      expect(native_activity.errors[:base]).to include('Relationship identity mismatch')
    end
  end
end
