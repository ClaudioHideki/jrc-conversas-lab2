# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcContactCenter::CustomerContext do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:user) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:context) { { account: account, user: user, account_user: account.account_users.find_by!(user: user) } }
  let(:phone) { '+5511999999999' }

  it 'uses the linked contact inside the call account without guessing another customer by phone' do
    contact = create(:contact, account: account, phone_number: phone)
    call = JrcContactCenter::CallSession.new(account: account, contact: contact, ani: '81103', direction: 'inbound')

    result = described_class.new(account: account, user_context: context).for_call(call)

    expect(result[:status]).to eq('identified')
    expect(result[:contacts]).to contain_exactly(include(id: contact.id.to_s))
  end

  it 'never treats a short internal extension or a SIP URI as a customer phone' do
    contact = create(:contact, account: account, phone_number: phone)
    contact.update_column(:phone_number, '81103')

    expect(described_class.new(account: account, user_context: context).by_phone('81103')[:contacts]).to be_empty
    expect(described_class.new(account: account, user_context: context).by_phone("sip:#{phone}@pbx.example")[:contacts]).to be_empty
  end

  it 'rejects a call from another account and never returns its linked customer' do
    contact = create(:contact, account: other_account, phone_number: phone)
    call = JrcContactCenter::CallSession.new(account: other_account, contact: contact)

    expect { described_class.new(account: account, user_context: context).for_call(call) }.to raise_error(ArgumentError, 'call account mismatch')
  end

  it 'returns ambiguity explicitly without selecting the first contact' do
    create(:contact, account: account, phone_number: phone)
    contact = create(:contact, account: account)
    contact.update_column(:phone_number, phone.delete_prefix('+'))
    call = JrcContactCenter::CallSession.new(account: account, ani: phone, direction: 'inbound')

    result = described_class.new(account: account, user_context: context).for_call(call)

    expect(result[:status]).to eq('ambiguous')
    expect(result[:ambiguous]).to be(true)
    expect(result[:contacts].length).to eq(2)
  end

  it 'resolves customer context using existing master companies and excludes another account' do
    company = account.master_companies.create!(name: 'Customer', customer_code: 'EMP-000001')
    contact = create(:contact, account: account, company_id: company.id, phone_number: phone)
    create(:contact, account: other_account, phone_number: phone)

    result = described_class.new(account: account, user_context: context).by_phone(phone)

    expect(result[:ambiguous]).to be(false)
    expect(result[:contacts]).to contain_exactly(include(id: contact.id.to_s, company: include(id: company.id.to_s, customer_code: 'EMP-000001')))
  end

  context 'with the existing customer master directory' do
    let(:contact) { create(:contact, account: account, phone_number: phone) }
    let(:call) do
      JrcContactCenter::CallSession.create!(account: account, contact: contact, ani: phone, direction: 'inbound', status: 'connected',
                                            provider: 'synthetic', correlation_id: SecureRandom.uuid, started_at: Time.current)
    end

    before { account.enable_features!('jrc_contact_center', 'jrc_customer_master', 'custom_roles') }

    it 'offers only the linked identifier authorized by the native directory' do
      result = described_class.new(account: account, user_context: context).for_call(call)
      expect(result[:directory]).to eq(contact_id: contact.id.to_s)
      expect(result[:contacts]).to contain_exactly(include(id: contact.id.to_s))
      expect(result[:status]).to eq('identified')
      expect(result[:identity_source]).to eq('call_contact_link')
    end

    it 'keeps the prior call context but hides the master entry when that native module is unavailable' do
      account.disable_features!('jrc_customer_master')
      result = described_class.new(account: account, user_context: context).for_call(call)
      expect(result[:status]).to eq('identified')
      expect(result[:directory]).to be_nil
      expect(result[:contacts]).to contain_exactly(include(id: contact.id.to_s))
    end

    it 'never promotes one telephone candidate into a confirmed master link' do
      contact
      unlinked = JrcContactCenter::CallSession.new(account: account, ani: phone, direction: 'inbound')
      result = described_class.new(account: account, user_context: context).for_call(unlinked)
      expect(result[:status]).to eq('identified')
      expect(result[:contacts]).to contain_exactly(include(id: contact.id.to_s))
      expect(result).not_to have_key(:directory)
      expect(result[:identity_source]).to eq('phone_candidates')
      expect(unlinked.contact_id).to be_nil
    end

    it 'does not convert Call Center configure or operate rights into native contact management rights' do
      role = create(:custom_role, account: account,
                                  permissions: %w[jrc_contact_center_view jrc_contact_center_operate jrc_contact_center_configure])
      context[:account_user].update!(role: :agent, custom_role: role)
      result = described_class.new(account: account, user_context: context).for_call(call)
      expect(result[:status]).to eq('identified')
      expect(result[:directory]).to be_nil
      expect(result[:contacts]).to contain_exactly(include(id: contact.id.to_s))
    end

    it 'rechecks native directory permission after a role changes without removing the call history' do
      role = create(:custom_role, account: account,
                                  permissions: %w[contact_manage jrc_contact_center_view jrc_contact_center_operate jrc_contact_center_configure])
      context[:account_user].update!(role: :agent, custom_role: role)
      service = described_class.new(account: account, user_context: context)
      expect(service.for_call(call)[:directory]).to eq(contact_id: contact.id.to_s)
      role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_operate jrc_contact_center_configure])
      expect(service.for_call(call)[:directory]).to be_nil
      expect(call.reload.contact_id).to eq(contact.id)
    end
  end
end
