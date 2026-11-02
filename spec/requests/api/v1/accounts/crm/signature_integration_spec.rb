require 'rails_helper'

RSpec.describe 'Backoffice DocuSign configuration', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/signature_integration" }
  let(:private_key) { OpenSSL::PKey::RSA.new(2048).to_pem }
  let(:attributes) do
    { environment: 'demo', integration_key: SecureRandom.uuid, impersonated_user_id: SecureRandom.uuid,
      external_account_id: SecureRandom.uuid, private_key: private_key,
      connect_hmac_keys: ['synthetic-connect-key-for-tests-only-1234'], enabled: true }
  end

  before { account.enable_features!('jrc_crm') }

  it 'saves encrypted credentials but returns no private key or Connect secret and no false ready state' do
    patch base, params: { integration: attributes, revision: 0 }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('configured' => true, 'can_manage' => true, 'delivery_ready' => false, 'revision' => 1)
    expect(response.body).not_to include('BEGIN RSA PRIVATE KEY', 'synthetic-connect-key-for-tests-only-1234')
    record = JrcBackoffice::SignatureIntegration.find_by!(account_id: account.id)
    expect(record.credentials['private_key']).to eq(private_key.strip)
    expect(record.encrypted_credentials).not_to include('PRIVATE KEY')
    expect(JrcCrm::AuditEvent.where(account: account, actor_type: 'User', actor_id: admin.id, event_type: 'signature_configuration_updated')).to exist
  end

  it 'does not use a submitted native account ID to save into another tenant' do
    foreign = create(:account)
    patch base, params: { integration: attributes.merge(account_id: foreign.id), revision: 0 }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(JrcBackoffice::SignatureIntegration.where(account_id: foreign.id)).not_to exist
    expect(JrcBackoffice::SignatureIntegration.where(account_id: account.id)).to exist
  end

  it 'requires an administrator with group coverage to manage global credentials when the organization is configured' do
    issuer = account.master_companies.create!(name: 'TESTE SINTÉTICO — Operadora', relationship_type: 'internal')
    unit = account.jrc_crm_business_units.create!(name: 'TESTE SINTÉTICO — Unidade', code: 'signature-unit', company_id: issuer.id)
    JrcCrm::UserBusinessUnit.create!(account: account, user: admin, business_unit: unit, scope: 'BUSINESS_UNIT', structure_managed: true)
    patch base, params: { integration: attributes, revision: 0 }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcBackoffice::SignatureIntegration.where(account_id: account.id)).not_to exist
  end

  it 'does not let an agent create configuration or see management details' do
    agent = create(:user, account: account, role: :agent)
    patch base, params: { integration: attributes, revision: 0 }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    get base, headers: agent.create_new_auth_token
    expect(response.parsed_body).to include('configured' => false, 'can_manage' => false)
    expect(response.parsed_body).not_to have_key('details')
  end

  it 'refuses a stale configuration save without replacing the original credentials' do
    record = JrcBackoffice::SignatureConfiguration.new(account: account, actor: admin).save!(attributes: attributes, expected_revision: 0)
    before = record.encrypted_credentials
    patch base, params: { integration: attributes.merge(external_account_id: SecureRandom.uuid), revision: 0 }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(record.reload.encrypted_credentials).to eq(before)
  end

  it 'records only real OAuth authorization confirmation and still requires a separate Connect check' do
    record = JrcBackoffice::SignatureConfiguration.new(account: account, actor: admin).save!(attributes: attributes, expected_revision: 0)
    stub_request(:post, 'https://account-d.docusign.com/oauth/token')
      .to_return(status: 200, body: { access_token: 'synthetic-token-only', expires_in: 3600 }.to_json)
    stub_request(:get, 'https://account-d.docusign.com/oauth/userinfo').to_return(status: 200, body: {
      sub: record.impersonated_user_id,
      accounts: [{ account_id: record.external_account_id, base_uri: 'https://demo.docusign.net' }]
    }.to_json)
    post "#{base}/check", params: { revision: record.revision }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('authorization_checked' => true, 'connect_checked' => false, 'delivery_ready' => false)
  end

  it 'does not record OAuth success when consent is missing' do
    record = JrcBackoffice::SignatureConfiguration.new(account: account, actor: admin).save!(attributes: attributes, expected_revision: 0)
    stub_request(:post, 'https://account-d.docusign.com/oauth/token').to_return(status: 400, body: '{"error":"consent_required"}')
    post "#{base}/check", params: { revision: record.revision }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('code' => 'CONSENT_REQUIRED')
    expect(record.reload.authorization_checked_at).to be_nil
  end

  it 'redacts both private credentials in native request logging' do
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter('integration' => attributes.stringify_keys)
    expect(filtered['integration']).to include('private_key' => '[FILTERED]', 'connect_hmac_keys' => '[FILTERED]')
  end

  it 'does not confirm authorization when management permission is revoked during the provider call' do
    record = JrcBackoffice::SignatureConfiguration.new(account: account, actor: admin).save!(attributes: attributes, expected_revision: 0)
    stub_request(:post, 'https://account-d.docusign.com/oauth/token')
      .to_return(status: 200, body: { access_token: 'synthetic-token-only', expires_in: 3600 }.to_json)
    stub_request(:get, 'https://account-d.docusign.com/oauth/userinfo').to_return do
      member = account.account_users.find_by!(user_id: admin.id)
      database = ActiveRecord::Base.connection
      # Preserve the request cache while changing the actual database role.
      database.raw_connection.exec("UPDATE account_users SET role=#{database.quote(AccountUser.roles.fetch('agent'))} WHERE id=#{member.id}")
      { status: 200, body: { sub: record.impersonated_user_id,
                             accounts: [{ account_id: record.external_account_id, base_uri: 'https://demo.docusign.net' }] }.to_json }
    end
    post "#{base}/check", params: { revision: record.revision }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(record.reload.authorization_checked_at).to be_nil
  end

  it 'rejects a late authorization confirmation for an older configuration revision' do
    configuration = JrcBackoffice::SignatureConfiguration.new(account: account, actor: admin)
    record = configuration.save!(attributes: attributes, expected_revision: 0)
    stub_request(:post, 'https://account-d.docusign.com/oauth/token')
      .to_return(status: 200, body: { access_token: 'synthetic-token-only', expires_in: 3600 }.to_json)
    stub_request(:get, 'https://account-d.docusign.com/oauth/userinfo').to_return do
      configuration.save!(attributes: attributes, expected_revision: record.revision)
      { status: 200, body: { sub: record.impersonated_user_id,
                             accounts: [{ account_id: record.external_account_id, base_uri: 'https://demo.docusign.net' }] }.to_json }
    end
    post "#{base}/check", params: { revision: record.revision }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(record.reload).to have_attributes(revision: 2, authorization_checked_at: nil, connect_checked_at: nil)
  end

  it 'preserves encrypted credentials when editing public settings while invalidating both prior verifications' do
    record = JrcBackoffice::SignatureConfiguration.new(account: account, actor: admin).save!(attributes: attributes, expected_revision: 0)
    record.update!(authorization_checked_at: Time.current, connect_checked_at: Time.current)
    patch base, params: { integration: { enabled: false }, revision: 1 }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(record.reload).to have_attributes(revision: 2, enabled: false, authorization_checked_at: nil, connect_checked_at: nil)
    expect(record.credentials).to include('private_key' => private_key.strip, 'connect_hmac_keys' => attributes[:connect_hmac_keys])
    expect(response.body).not_to include('PRIVATE KEY', attributes[:connect_hmac_keys].first)
  end

  it 'preserves the historical creator after membership removal while checking the replacement administrator permission' do
    record = JrcBackoffice::SignatureConfiguration.new(account: account, actor: admin).save!(attributes: attributes, expected_revision: 0)
    replacement = create(:user, account: account, role: :administrator)
    account.account_users.find_by!(user_id: admin.id).destroy!
    patch base, params: { integration: { enabled: false }, revision: 1 }, headers: replacement.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(record.reload).to have_attributes(created_by_id: admin.id, revision: 2, enabled: false)
    expect(record.credentials['private_key']).to eq(private_key.strip)
    audit = JrcCrm::AuditEvent.where(account: account, event_type: 'signature_configuration_updated').order(:id).last
    expect(audit.actor_id).to eq(replacement.id)
  end
end
