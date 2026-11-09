# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Distinct portal histories with concurrent shared contact channels', :sd_concurrency, type: :service do
  self.use_transactional_tests = false
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskConcurrency

  it 'creates three people and separate tickets without treating collective channels as identity' do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master')
    company = sd_account.master_companies.create!(name: 'Synthetic shared-channel customer', relationship_type: 'customer')
    actor = sd_user
    account = sd_account
    operations = %w[Joao Maria Pedro].map do |name|
      lambda do
        JrcCustomers::RequesterWriter.new(account: account, actor: actor).create!(company: company,
          attributes: { name: name, email: 'collective@example.test', phone_number: '(61) 99999-9999' }, request_key: name).id
      end
    end
    results = concurrently(operations)
    expect(results).to all(be_a(Integer))
    expect(results.uniq.size).to eq(3)
    widget = create(:channel_widget, account: sd_account)
    sd_status
    service = JrcServiceDesk::Service.create!(account: sd_account, unit: sd_unit, code: 'shared-channel-test', name: 'Synthetic service',
      active: true, portal_enabled: true, default_priority: sd_priority, portal_inbox: widget.inbox, portal_execution_membership: sd_membership)
    identities = results.map { |id| create(:contact_inbox, contact: Contact.find(id), inbox: widget.inbox, hmac_verified: true) }
    revision = JrcServiceDesk::ConfigurationResources.revision('services', service)
    tickets = concurrently(identities.map do |identity|
      lambda do
        proof = JrcServiceDesk::PortalIdentityProof.new(identifier: identity.contact.identifier,
          token: OpenSSL::HMAC.hexdigest('sha256', widget.hmac_token, identity.contact.identifier))
        JrcServiceDesk::PortalCreationService.new(contact_inbox: identity, identity_proof: proof).call(
          attributes: { service_id: service.id, service_revision: revision, title: 'Individual request', service_fields: {} },
          idempotency_key: 'same-client-key-per-person').ticket_id
      end
    end)
    expect(tickets).to all(be_a(Integer))
    expect(tickets.uniq.size).to eq(3)
    identities.each do |identity|
      proof = JrcServiceDesk::PortalIdentityProof.new(identifier: identity.contact.identifier,
        token: OpenSSL::HMAC.hexdigest('sha256', widget.hmac_token, identity.contact.identifier))
      scope = JrcServiceDesk::PortalScope.new(contact_inbox: identity, identity_proof: proof)
      expect(scope.tickets.pluck(:requester_id)).to eq([identity.contact_id])
      expect(scope.tickets.count).to eq(1)
      expect(JrcServiceDesk::RequesterContactDetails.notification_recipient(identity.contact, 'email')).to be_nil
    end
  end
end
