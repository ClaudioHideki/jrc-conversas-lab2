require 'rails_helper'
require Rails.root.join('db/migrate/20261102030000_create_customer_signing_identities')

RSpec.describe JrcCustomers::SigningIdentity do
  it 'reverses and reapplies the protected extension without changing native Contact or conversation data' do
    raise 'Disposable database required' unless Rails.env.test? && ENV['POSTGRES_DATABASE'] == 'jrc_rel_v2_candidate_test'

    connection = ActiveRecord::Base.connection
    conversation = create(:conversation)
    contact = conversation.contact
    original = contact.reload.attributes
    counts = [Account.count, Contact.count, Conversation.count, Message.count]
    expect(described_class.count).to eq(0)
    CreateCustomerSigningIdentities.new.migrate(:down)
    expect(connection.table_exists?(:jrc_customer_signing_identities)).to be(false)
    CreateCustomerSigningIdentities.new.migrate(:up)
    expect([Account.count, Contact.count, Conversation.count, Message.count]).to eq(counts)
    expect(contact.reload.attributes).to eq(original)
    expect(connection.index_exists?(:jrc_customer_signing_identities, %i[account_id contact_id], unique: true)).to be(true)
    expect(connection.index_exists?(:jrc_customer_signing_identities, %i[account_id lookup_digest], unique: true)).to be(true)
    expect(connection.foreign_keys(:jrc_customer_signing_identities).map(&:name)).to include('jrc_signing_identity_contact_tenant')
  ensure
    ActiveRecord::Base.connection.schema_cache.clear!
  end
end
