require 'rails_helper'

RSpec.describe 'Customer contact attribute boundary', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, identifier: 'preserved') }

  before { account.enable_features!('jrc_customer_master') }

  it 'keeps existing HTTP strong parameters when internal bulk writes gain native metadata and label support' do
    original = contact.reload.attributes
    values = { identifier: 'forged', custom_attributes: { role: 'admin' }, additional_attributes: { city: 'forged' },
               label_list: ['forged'], account_id: 0 }
    endpoint = "/api/v1/accounts/#{account.id}/customers/contacts/#{contact.id}"
    patch endpoint, headers: actor.create_new_auth_token, params: { contact: values }, as: :json
    expect(response).to have_http_status(:ok)
    expect(contact.reload.identifier).to eq('preserved')
    expect(contact.custom_attributes).to eq(original.fetch('custom_attributes'))
    expect(contact.additional_attributes).to eq(original.fetch('additional_attributes'))
    expect(contact.label_list).to be_empty
    expect(contact.account_id).to eq(account.id)
  end
end
