require 'rails_helper'

RSpec.describe 'Backoffice signature history API', :approval_core, :authority_core, :signature_delivery_core, type: :request do
  let(:domain) { admitted_signature_domain }
  let(:account) { domain.fetch(:account) }
  let(:actor) { domain.fetch(:actor) }
  let(:delivery) { domain.fetch(:delivery) }
  let(:headers) { actor.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/backoffice_requests/#{domain[:operation].id}/contract_signatures" }

  before do
    raise 'Owned history API database required' unless Rails.env.test? && ENV['POSTGRES_DATABASE'] == 'jrc_four_domains_schema_admission_test'

    domain
    role = create(:custom_role, account: account, permissions: %w[jrc_crm jrc_approvals_request_create])
    account.account_users.find_by!(user: actor).update!(role: :agent, custom_role: role)
  end

  it 'returns only bounded persisted facts to the assigned agent without provider I/O or signature claims' do
    expect(JrcBackoffice::Signatures::Gateway).not_to receive(:new)
    get url, headers: headers, params: { page: 999 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 0)).to include('id' => delivery.id, 'state' => 'prepared', 'version_number' => domain[:version].number)
    expect(response.parsed_body.fetch('meta')).to include('page' => 1, 'per_page' => 10, 'total' => 1)
    expect(response.parsed_body).to include('signature_requirement_satisfied' => false, 'contract' => include('signature_verified' => false))
    expect(response.headers).to include('Cache-Control' => 'no-store', 'X-Content-Type-Options' => 'nosniff')
    expect(response.body).not_to include('source_snapshot', 'transaction_id', 'recipients', '11144477735', '52998224725',
                                         'private_key', 'connect_hmac_keys', domain[:connection].external_account_id)
  end

  it 'paginates event facts on the server and excludes encrypted payload details' do
    # Artificial history volume for pagination/privacy, not real provider sends.
    22.times do |index|
      delivery.events.create!(account: account, connection: delivery.connection, kind: 'send_uncertain', event_key: "synthetic-history-#{index}",
                              source_snapshot: '{"code":"PRIVATE_INTERNAL_DETAIL"}')
    end
    get "#{url}/#{delivery.id}", headers: headers, params: { page: 1 }
    expect(response).to have_http_status(:ok)
    first = response.parsed_body
    expect(first.fetch('data').length).to eq(20)
    expect(first.fetch('meta')).to include('page' => 1, 'pages' => 2, 'total' => 23)
    get "#{url}/#{delivery.id}", headers: headers, params: { page: 2 }
    expect(response.parsed_body.fetch('data').length).to eq(3)
    expect(response.parsed_body.fetch('data').pluck('id') & first.fetch('data').pluck('id')).to be_empty
    expect(response.body).not_to include('PRIVATE_INTERNAL_DETAIL', 'source_snapshot', 'private_key')
    expect(domain[:contract].reload.signature_status).to eq('not_started')
  end

  it 'denies other accounts, nonowners and withdrawn unit coverage including direct history URLs' do
    outsider = approval_actor(domain, permissions: %w[jrc_crm jrc_approvals_decide])
    get url, headers: outsider.user.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    foreign = create(:user, account: create(:account), role: :administrator)
    get "#{url}/#{delivery.id}", headers: foreign.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    account.jrc_crm_user_business_units.where(user: actor).each { |row| row.update!(active: false) }
    get url, headers: headers
    expect(response).to have_http_status(:not_found)
    get "#{url}/#{delivery.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'does not count an old delivery whose sealed unit is outside current coverage even when the relocated origin is visible' do
    JrcBackoffice::Signatures::Admissions.new(account: account, actor: actor, request_id: domain[:operation].id).cancel_prepared!(delivery.id)
    destination = account.jrc_crm_business_units.create!(name: 'TESTE SINTÉTICO — Destino', code: SecureRandom.hex(8),
                                                         company_id: domain[:company].id)
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: domain[:company], business_unit: destination,
                                                active: true, structure_managed: true)
    # Hostile/legacy relocation after terminal cancellation; immutable delivery
    # history remains under its original coverage, never the current origin.
    [domain[:operation], domain[:order], domain[:contract]].each do |record|
      ApplicationRecord.connection.execute("UPDATE #{record.class.table_name} SET business_unit_id=#{destination.id} WHERE id=#{record.id}")
    end
    account.jrc_crm_user_business_units.where(user: actor, business_unit: domain[:unit]).each { |row| row.update!(active: false) }
    get url, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('data')).to be_empty
    expect(response.parsed_body.dig('meta', 'total')).to eq(0)
    get "#{url}/#{delivery.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(delivery.reload.state).to eq('canceled')
  end
end
