require 'rails_helper'
RSpec.describe 'Operator routes', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:headers) { user.create_new_auth_token }

  it 'reports OFF without contacting either external system' do
    expect(JrcOperator::Client).not_to receive(:new)
    get "/api/v1/accounts/#{account.id}/operator/context", headers: user.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['enabled']).to be(false)
    get "/api/v1/accounts/#{account.id}/operator/bindings", headers: user.create_new_auth_token
    expect(response.status).to eq(403), response.body
  end

  it 'rejects direct API writes by an administrator without an explicit grant' do
    account.enable_features!('jrc_operator')
    expect(JrcOperator::Client).not_to receive(:new)
    reservation_params = { key: 'synthetic-request-key', reservation: { number_id: '1', order_ref: '1' } }
    post "/api/v1/accounts/#{account.id}/operator/bindings/1/reserve", headers: user.create_new_auth_token, params: reservation_params
    expect(response.status).to eq(403), response.body
  end

  it 'does not allow a member to change the account in a direct URL' do
    other = create(:account)
    expect(JrcOperator::Client).not_to receive(:new)
    get "/api/v1/accounts/#{other.id}/operator/bindings", headers: user.create_new_auth_token
    expect(response.status).to be_in([401, 403, 404])
  end

  context 'when the operator has explicit permissions and unit membership' do
    let(:company) { JrcCustomers::Company.create!(account: account, name: 'Synthetic issuer', relationship_type: 'internal') }
    let(:unit) { JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: 'Synthetic unit', code: 'SYNTHETIC') }
    let(:contact) { create(:contact, account: account) }
    let(:binding) do
      JrcOperator::Binding.create!(account: account, company: company, business_unit: unit, contact: contact,
                                   bemtevi_customer_id: '777', active: true)
    end
    let(:order) do
      JrcCrm::SalesOrder.create!(account: account, owner: user, business_unit: unit, contact: contact,
                                 order_origin: 'direct_sale', source_type: 'manual', status: 'draft')
    end
    let(:client) { instance_double(JrcOperator::Client) }

    before do
      account.enable_features!('jrc_operator', 'jrc_crm')
      permissions = JrcOperator::Access::PERMISSIONS + %w[jrc_crm conversation_manage]
      role = create(:custom_role, account: account, permissions: permissions)
      account.account_users.find_by!(user: user).update!(custom_role: role)
      JrcCrm::UserBusinessUnit.create!(account: account, user: user, company: company, business_unit: unit,
                                       scope: 'BUSINESS_UNIT', structure_managed: true, active: true)
      allow(JrcOperator::Client).to receive(:new).and_return(client)
    end

    it 'offers only the selected customer orders and explicitly allowed conversations' do
      order
      inbox = create(:inbox, account: account)
      binding.update!(allowed_inbox_ids: [inbox.id])
      conversation = create(:conversation, account: account, contact: contact, inbox: inbox)
      create(:conversation, account: account, contact: contact)
      create(:conversation, account: account, inbox: inbox)
      JrcCrm::SalesOrder.create!(account: account, owner: user, business_unit: unit, contact: create(:contact, account: account),
                                 order_origin: 'direct_sale', source_type: 'manual', status: 'draft')
      allow(client).to receive(:rede).with(:ddds, { 'external_actor' => user.id.to_s }).and_return('items' => [])
      get "/api/v1/accounts/#{account.id}/operator/bindings/#{binding.id}/options", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('orders').pluck('id')).to eq([order.id])
      expect(response.parsed_body.fetch('conversations').pluck('id')).to eq([conversation.id])
    end

    it 'generates the native order reference on the server for an authorized reservation' do
      command = instance_double(JrcOperator::Commands)
      operation = binding.operations.create!(user: user, kind: 'reserve', key: 'synthetic-request-key-001')
      allow(JrcOperator::Commands).to receive(:new).with(binding: binding, user: user).and_return(command)
      expect(command).to receive(:remote!).with('reserve', { 'number_id' => 'synthetic', 'order_ref' => "jrc:#{account.id}:order:#{order.id}" },
                                                'synthetic-request-key-001').and_return(operation)
      reservation_params = { key: 'synthetic-request-key-001', reservation: { number_id: 'synthetic', order_ref: order.id } }
      post "/api/v1/accounts/#{account.id}/operator/bindings/#{binding.id}/reserve", headers: headers, as: :json, params: reservation_params
      expect(response).to have_http_status(:ok)
    end

    it 'denies another customer order before creating a remote command' do
      other = JrcCrm::SalesOrder.create!(account: account, owner: user, business_unit: unit, contact: create(:contact, account: account),
                                         order_origin: 'direct_sale', source_type: 'manual', status: 'draft')
      expect(JrcOperator::Commands).not_to receive(:new)
      reservation_params = { key: 'synthetic-request-key-001', reservation: { number_id: 'synthetic', order_ref: other.id } }
      post "/api/v1/accounts/#{account.id}/operator/bindings/#{binding.id}/reserve", headers: headers, as: :json, params: reservation_params
      expect(response).to have_http_status(:not_found)
      expect(binding.operations.count).to eq(0)
    end

    it 'retains the CRM permission gate even when reservation parameters are missing' do
      account.disable_features!('jrc_crm')
      expect(JrcOperator::Commands).not_to receive(:new)
      post "/api/v1/accounts/#{account.id}/operator/bindings/#{binding.id}/reserve", headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end
