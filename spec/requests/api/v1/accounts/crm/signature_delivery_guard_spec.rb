require 'rails_helper'

RSpec.describe 'CRM signature delivery evidence guard', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }
  let(:order) { account.jrc_crm_sales_orders.create!(owner: admin, contact: contact, status: 'approved') }
  let(:contract) do
    account.jrc_crm_contracts.create!(sales_order: order, contact: contact, owner: admin, signature_mode: 'provider',
                                      signature_provider: 'docusign', signature_status: 'prepared', status: 'awaiting_signature')
  end
  let(:url) { "/api/v1/accounts/#{account.id}/crm/contracts/#{contract.id}/send_for_signature" }

  before { account.enable_features!('jrc_crm') }

  it 'does not turn a typed external ID into a delivery fact or audit a send that never happened' do
    post url, params: { external_id: SecureRandom.uuid }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('VERSIONED_DELIVERY_REQUIRED')
    expect(contract.reload).to have_attributes(signature_status: 'prepared', signature_external_id: nil)
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'contract_signature_sent')).not_to exist
  end

  it 'preserves a historical identifier instead of replacing it with a caller-supplied ID' do
    contract.update!(signature_external_id: 'legacy-evidence-reference')
    post url, params: { external_id: SecureRandom.uuid, provider: 'not-installed' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(contract.reload.signature_external_id).to eq('legacy-evidence-reference')
  end

  it 'keeps the native owner and tenant boundaries on the existing route' do
    agent = create(:user, account: account, role: :agent)
    post url, params: { external_id: SecureRandom.uuid }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    foreign = create(:account)
    foreign_admin = create(:user, account: foreign, role: :administrator)
    post url, params: { external_id: SecureRandom.uuid }, headers: foreign_admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(contract.reload.signature_status).to eq('prepared')
  end

  %w[active expiring renewed].each do |status|
    it "holds #{status} independently from the registered customer signature" do
      request = account.jrc_crm_backoffice_requests.create!(
        sales_order: order, contract: contract, owner: admin, requested_by: admin,
        contact: contact, request_kind: 'fulfillment', stage: 'contract',
        title: 'TESTE SINTÉTICO — Ativação', metadata: { contract_required: true }
      )
      contract.signed_document.attach(io: StringIO.new(File.binread(Rails.root.join('spec/fixtures/files/sample.pdf'))),
                                      filename: 'synthetic-customer-signature.pdf', content_type: 'application/pdf')
      contract.update!(signature_status: 'signed', signed_at: Time.current, signed_by_name: 'TESTE SINTÉTICO — Cliente')
      patch "/api/v1/accounts/#{account.id}/crm/contracts/#{contract.id}", params: { contract: { status: status } },
                                                                           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['code']).to eq('SIGNATURE_EVIDENCE_REQUIRED')
      expect(contract.reload).to have_attributes(status: 'awaiting_signature', signature_status: 'signed')
      expect(request.reload.stage).to eq('contract')
    end
  end
end
