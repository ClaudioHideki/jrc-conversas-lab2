require 'rails_helper'

RSpec.describe 'Backoffice signer directory permission preview', :approval_core, :authority_core, :signature_delivery_core, type: :request do
  let(:domain) { admitted_signature_domain }
  let(:account) { domain.fetch(:account) }
  let(:actor) { domain.fetch(:actor) }
  let(:role) { create(:custom_role, account: account, permissions: %w[jrc_crm jrc_approvals_request_create]) }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/backoffice_requests/#{domain[:operation].id}/contract_versions" }

  before do
    raise 'Owned version permission database required' unless Rails.env.test? && ENV['POSTGRES_DATABASE'] == 'jrc_four_domains_schema_admission_test'

    JrcBackoffice::Signatures::Admissions.new(account: account, actor: actor, request_id: domain[:operation].id)
                                         .cancel_prepared!(domain[:delivery].id)
    account.account_users.find_by!(user: actor).update!(role: :agent, custom_role: role)
  end

  it 'explains a missing directory permission and rejects direct generation without changing the contract or immutable version' do
    original = domain[:version].pdf_blob.download
    count = JrcBackoffice::ContractVersion.where(account: account).count
    get url, headers: actor.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('writable' => true, 'signer_directory_access' => false)
    digest = response.parsed_body.dig('contract', 'source_digest')
    post url, headers: actor.create_new_auth_token,
              params: { idempotency_key: SecureRandom.uuid, expected_source_digest: digest,
                        change_reason: 'TESTE SINTÉTICO — Sem permissão.' }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcBackoffice::ContractVersion.where(account: account).count).to eq(count)
    expect(domain[:version].reload.pdf_blob.download).to eq(original)
    expect(domain[:contract].reload.signature_status).to eq('not_started')
  end

  it 'allows an assigned agent with directory permission but still denies generation after unit coverage is revoked' do
    role.update!(permissions: role.permissions + ['contact_manage'])
    get url, headers: actor.create_new_auth_token
    expect([response.status, response.parsed_body.fetch('signer_directory_access')]).to eq([200, true])
    post url, headers: actor.create_new_auth_token,
              params: { idempotency_key: SecureRandom.uuid, expected_source_digest: response.parsed_body.dig('contract', 'source_digest'),
                        change_reason: 'TESTE SINTÉTICO — Agente com acesso aos contatos.' }, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include('number' => domain[:version].number + 1, 'created_by_id' => actor.id)
    count = JrcBackoffice::ContractVersion.where(account: account).count
    account.jrc_crm_user_business_units.where(user: actor).each { |grant| grant.update!(active: false) }
    get url, headers: actor.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    post url, headers: actor.create_new_auth_token,
              params: { idempotency_key: SecureRandom.uuid, change_reason: 'TESTE SINTÉTICO — Unidade revogada.' }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(JrcBackoffice::ContractVersion.where(account: account).count).to eq(count)
    expect(WebMock).not_to have_requested(:any, /docusign/)
  end
end
