# frozen_string_literal: true

require 'rails_helper'

# Exercise the unchanged call/customer APIs reused by recording details. Never grant native directory access from a recording right.
RSpec.describe 'Native authorized call context reused by recordings', :pabx do
  include_context 'with native authorized quality review source'

  let(:path) { "/api/v1/accounts/#{account.id}/jrc_contact_center/call_sessions/#{source_call.id}" }
  let(:headers) { actor.create_new_auth_token }
  let(:contact) { create(:contact, account: account, company_id: company.id, name: 'SYNTHETIC authorized recording customer') }
  let(:directory_rights) { recording_rights + %w[jrc_contact_center_operate contact_manage] }

  before do
    account.enable_features!('jrc_customer_master')
    role.update!(permissions: directory_rights)
    source_call.update!(contact_id: contact.id, company_id: company.id)
  end

  it 'returns only the explicitly linked covered customer and separately authorized native master entry' do
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('account_id')).to eq(account.id.to_s)
    item = response.parsed_body.fetch('item')
    expect(item).to include('id' => source_call.id, 'external_session_id' => record.external_unique_id, 'contact_id' => contact.id)
    expect(item.fetch('customer')).to include('status' => 'identified', 'identity_source' => 'call_contact_link',
                                              'directory' => { 'contact_id' => contact.id.to_s })
    expect(item.fetch('customer').fetch('contacts')).to contain_exactly(include('id' => contact.id.to_s, 'name' => contact.name))
  end

  it 'preserves authorized call context while denying master access without its independent native right' do
    role.update!(permissions: directory_rights - ['contact_manage'])
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    customer = response.parsed_body.fetch('item').fetch('customer')
    expect(customer).to include('status' => 'identified', 'directory' => nil)
    expect(customer.fetch('contacts')).to contain_exactly(include('id' => contact.id.to_s))
    expect(role.reload.permissions).not_to include('contact_manage')
  end

  it 'does not convert listening or human-review rights into customer operational access' do
    role.update!(permissions: recording_rights + ['jrc_contact_center_quality_review'])
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item').fetch('customer')).to eq('status' => 'restricted', 'contacts' => [], 'ambiguous' => false)
    expect(response.body).not_to include(contact.name)
  end

  it 'revalidates the current corporate coverage on the reused call read before returning customer context' do
    account.jrc_crm_user_business_units.where(user: actor).find_each { |coverage| coverage.update!(active: false) }
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(contact.name)
    expect(source_call.reload.contact_id).to eq(contact.id)
  end

  it 'revalidates native master access after a role changes without modifying the explicit customer link' do
    get path, headers: headers, as: :json
    expect(response.parsed_body.fetch('item').fetch('customer').fetch('directory')).to eq('contact_id' => contact.id.to_s)
    role.update!(permissions: directory_rights - ['contact_manage'])
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item').fetch('customer').fetch('directory')).to be_nil
    expect(source_call.reload.contact_id).to eq(contact.id)
  end

  it 'denies a nonmember Account before exposing the linked call or customer' do
    foreign = create(:account)
    get path.sub("accounts/#{account.id}", "accounts/#{foreign.id}"), headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(contact.name, record.external_unique_id)
  end
end
