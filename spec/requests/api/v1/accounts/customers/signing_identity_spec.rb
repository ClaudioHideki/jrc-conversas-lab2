require 'rails_helper'

RSpec.describe 'Customer master protected signing identity', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:company) { account.master_companies.create!(name: 'TESTE SINTÉTICO — Empresa', relationship_type: 'customer') }
  let(:contact) { create(:contact, account: account, company_id: company.id, name: 'TESTE SINTÉTICO — Representante') }
  let(:root) { "/api/v1/accounts/#{account.id}/customers" }
  let(:url) { "#{root}/contacts/#{contact.id}/signing_identity" }
  let(:cpf) { '52998224725' } # Public algorithm-validation fixture, not a real customer.
  let(:other_cpf) { '11144477735' }
  let(:input) { { identity: { personal_tax_identifier: cpf }, revision: 0 } }
  let(:writer) { JrcCustomers::SigningIdentityWriter.new(account: account, actor: admin) }

  before { account.enable_features!('jrc_customer_master') }

  it 'requires authentication and the native directory feature' do
    get url
    expect(response).to have_http_status(:unauthorized)
    account.disable_features!('jrc_customer_master')
    get url, headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns a missing identity without creating a second Contact or granting signing authority' do
    contact
    expect { get url, headers: headers }.not_to change(Contact, :count)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload']).to include('revision' => 0, 'personal_tax_identifier' => nil, 'signing_authority_verified' => false)
    expect(response.headers['Cache-Control']).to eq('no-store')
  end

  it 'encrypts a normalized identifier while keeping its native Contact and omitting it from generic JSON and audit' do
    patch url, params: { identity: { personal_tax_identifier: '529.982.247-25' }, revision: 0 }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    identity = contact.reload.signing_identity
    encrypted = identity.attributes_before_type_cast['personal_tax_identifier']
    expect(identity.personal_tax_identifier).to eq(cpf)
    expect(encrypted).not_to include(cpf)
    expect(identity.as_json.to_s).not_to include(cpf, 'lookup_digest')
    expect(response.parsed_body['payload']).to include('revision' => 1, 'personal_tax_identifier_masked' => '***.***.***-25',
                                                       'signing_authority_verified' => false)
    expect(JrcCrm::AuditEvent.where(account: account, resource_id: contact.id).pluck(:to_value).to_json).not_to include(cpf)
  end

  it 'does not treat an invalid identifier or a caller assertion of powers as verified identity' do
    patch url, params: { identity: { personal_tax_identifier: '11111111111', signing_authority_verified: true }, revision: 0 },
               headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(contact.signing_identity).to be_nil
    expect(response.body).not_to include('11111111111')
  end

  it 'rejects a stale edit without replacing the existing identifier' do
    writer.save!(contact_id: contact.id, personal_tax_identifier: cpf, expected_revision: 0)
    patch url, params: { identity: { personal_tax_identifier: other_cpf }, revision: 0 }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body).to eq('code' => 'IDENTITY_CHANGED')
    expect(contact.reload.signing_identity.personal_tax_identifier).to eq(cpf)
  end

  it 'does not use account, user or contact IDs supplied in the body to grant another scope' do
    foreign = create(:account)
    patch url, params: { identity: { personal_tax_identifier: cpf, account_id: foreign.id, contact_id: 999_999, user_id: 999_999 }, revision: 0 },
               headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(contact.reload.signing_identity).to have_attributes(account_id: account.id, contact_id: contact.id, created_by_id: admin.id)
    expect(JrcCustomers::SigningIdentity.where(account_id: foreign.id)).not_to exist
  end

  it 'denies another tenant contact even when its identifier is known' do
    foreign = create(:contact)
    get "#{root}/contacts/#{foreign.id}/signing_identity", headers: headers
    expect(response).to have_http_status(:not_found)
    patch "#{root}/contacts/#{foreign.id}/signing_identity", params: input, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'respects internal operator coverage in lookup, details, reassignment, and protected identity' do
    own_issuer = account.master_companies.create!(name: 'TESTE SINTÉTICO — Operadora A', relationship_type: 'internal')
    other_issuer = account.master_companies.create!(name: 'TESTE SINTÉTICO — Operadora B', relationship_type: 'internal')
    unit = account.jrc_crm_business_units.create!(name: 'TESTE SINTÉTICO — Unidade A', code: 'identity-unit', company_id: own_issuer.id)
    JrcCrm::UserBusinessUnit.create!(account: account, user: admin, business_unit: unit, scope: 'BUSINESS_UNIT', structure_managed: true)
    hidden = create(:contact, account: account, company_id: other_issuer.id)
    get "#{root}/contacts", headers: headers
    expect(response.parsed_body['payload'].pluck('id')).not_to include(hidden.id)
    get "#{root}/contacts/#{hidden.id}/signing_identity", headers: headers
    expect(response).to have_http_status(:not_found)
    get "#{root}/contacts/#{hidden.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    patch "#{root}/contacts/#{hidden.id}", params: { contact: { company_id: own_issuer.id }, confirm_reassignment: true }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(hidden.reload.company_id).to eq(other_issuer.id)
  end

  it 'requires the existing contact_manage permission for a custom-role agent' do
    agent = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: [])
    account.account_users.find_by!(user: agent).update!(custom_role: role)
    get url, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    patch url, params: input, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'keeps a single protected identity per person in the account' do
    writer.save!(contact_id: contact.id, personal_tax_identifier: cpf, expected_revision: 0)
    other = create(:contact, account: account, company_id: company.id)
    patch "#{root}/contacts/#{other.id}/signing_identity", params: input, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(other.signing_identity).to be_nil
    expect(JrcCustomers::SigningIdentity.where(account: account).count).to eq(1)
    expect(response.body).not_to include(cpf)
  end

  it 'reuses native duplicate detection before creating a Contact with an already registered personal identifier' do
    writer.save!(contact_id: contact.id, personal_tax_identifier: cpf, expected_revision: 0)
    expect do
      post "#{root}/contacts", params: { contact: { name: 'TESTE SINTÉTICO — Repetido', personal_tax_identifier: cpf, company_id: company.id } },
                               headers: headers, as: :json
    end.not_to change(Contact, :count)
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body).to include('code' => 'POSSIBLE_DUPLICATE')
    expect(response.parsed_body['candidates'].pluck('id')).to include(contact.id)
    expect(response.body).not_to include(cpf)
  end

  it 'does not bypass the unique personal identity by confirming a distinct Contact' do
    writer.save!(contact_id: contact.id, personal_tax_identifier: cpf, expected_revision: 0)
    expect do
      post "#{root}/contacts", params: { contact: { name: 'TESTE SINTÉTICO — Repetido', personal_tax_identifier: cpf }, confirm_distinct: true },
                               headers: headers, as: :json
    end.not_to change(Contact, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcCustomers::SigningIdentity.where(account: account).count).to eq(1)
  end

  it 'creates the canonical Contact and its protected identity atomically' do
    post "#{root}/contacts", params: { contact: { name: 'TESTE SINTÉTICO — Novo', personal_tax_identifier: cpf, company_id: company.id } },
                             headers: headers, as: :json
    expect(response).to have_http_status(:created)
    created = account.contacts.find(response.parsed_body['payload']['id'])
    expect(created.signing_identity.personal_tax_identifier).to eq(cpf)
    expect(created.signing_identity.created_by_id).to eq(admin.id)
    expect(response.body).not_to include(cpf)
  end

  it 'preserves the identifier when native merge removes its original Contact' do
    source = create(:contact, account: account, company_id: company.id)
    identity = writer.save!(contact_id: source.id, personal_tax_identifier: cpf, expected_revision: 0)
    post "#{root}/contacts/#{contact.id}/merge", params: { source_contact_id: source.id, confirm: true }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(Contact.where(id: source.id)).not_to exist
    expect(identity.reload).to have_attributes(contact_id: contact.id, revision: 2)
    expect(identity.personal_tax_identifier).to eq(cpf)
    expect(response.body).not_to include(cpf)
  end

  it 'preserves the identity through the native merge entrypoint when the directory feature is later disabled' do
    source = create(:contact, account: account, company_id: company.id)
    identity = writer.save!(contact_id: source.id, personal_tax_identifier: cpf, expected_revision: 0)
    account.disable_features!('jrc_customer_master')
    post "/api/v1/accounts/#{account.id}/actions/contact_merge", params: { base_contact_id: contact.id, mergee_contact_id: source.id },
                                                                 headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(identity.reload.contact_id).to eq(contact.id)
    expect(Contact.where(id: source.id)).not_to exist
  end

  it 'keeps protected-identity merges administrator-only when the directory UI is disabled' do
    source = create(:contact, account: account, company_id: company.id)
    writer.save!(contact_id: source.id, personal_tax_identifier: cpf, expected_revision: 0)
    agent = create(:user, account: account, role: :agent)
    account.disable_features!('jrc_customer_master')
    post "/api/v1/accounts/#{account.id}/actions/contact_merge", params: { base_contact_id: contact.id, mergee_contact_id: source.id },
                                                                 headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(source.reload.signing_identity.personal_tax_identifier).to eq(cpf)
  end

  it 'refuses merging different personal identities without deleting either Contact' do
    source = create(:contact, account: account, company_id: company.id)
    writer.save!(contact_id: contact.id, personal_tax_identifier: cpf, expected_revision: 0)
    writer.save!(contact_id: source.id, personal_tax_identifier: other_cpf, expected_revision: 0)
    post "#{root}/contacts/#{contact.id}/merge", params: { source_contact_id: source.id, confirm: true }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(Contact.where(id: [contact.id, source.id]).count).to eq(2)
    expect(JrcCustomers::SigningIdentity.where(account: account).count).to eq(2)
  end

  it 'does not fall back to plaintext if a stored encrypted value has been corrupted' do
    identity = writer.save!(contact_id: contact.id, personal_tax_identifier: cpf, expected_revision: 0)
    connection = ActiveRecord::Base.connection
    connection.execute("UPDATE jrc_customer_signing_identities SET personal_tax_identifier=#{connection.quote(cpf)} WHERE id=#{identity.id}")
    get url, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('code' => 'IDENTITY_UNAVAILABLE')
    expect(response.body).not_to include(cpf)
  end

  it 'redacts personal identifiers in native request logging' do
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
                                             .filter(identity: { personal_tax_identifier: cpf, cpf: cpf })
    expect(filtered[:identity].values).to all(eq('[FILTERED]'))
  end

  it 'does not disclose an uncovered internal contact through identity lookup' do
    issuer = account.master_companies.create!(name: 'TESTE SINTÉTICO — Operadora restrita', relationship_type: 'internal')
    hidden = create(:contact, account: account, company_id: issuer.id)
    get "#{root}/identity", params: { phone: hidden.phone_number, country: 'BR' }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload'].pluck('id')).not_to include(hidden.id)
  end

  it 'cannot modify the channels of an uncovered internal contact' do
    issuer = account.master_companies.create!(name: 'TESTE SINTÉTICO — Operadora restrita', relationship_type: 'internal')
    hidden = create(:contact, account: account, company_id: issuer.id)
    post "#{root}/contacts/#{hidden.id}/contact_points", params: { contact_point: { kind: 'email', value: 'hidden@example.test' } },
                                                         headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(hidden.contact_points).not_to exist
  end

  it 'rechecks actual directory access after decryption and returns no protected data after revocation' do
    writer.save!(contact_id: contact.id, personal_tax_identifier: cpf, expected_revision: 0)
    allow(JrcCustomers::SigningIdentity).to receive(:find_by).and_wrap_original do |lookup, **arguments|
      record = lookup.call(**arguments)
      allow(record).to receive(:personal_tax_identifier).and_wrap_original do |original|
        value = original.call
        account.disable_features!('jrc_customer_master')
        value
      end
      record
    end
    get url, headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(cpf)
  end

  it 'allows the same identifier in separate accounts with different protected lookup keys' do
    first = writer.save!(contact_id: contact.id, personal_tax_identifier: cpf, expected_revision: 0)
    foreign = create(:account)
    foreign.enable_features!('jrc_customer_master')
    user = create(:user, account: foreign, role: :administrator)
    person = create(:contact, account: foreign)
    second = JrcCustomers::SigningIdentityWriter.new(account: foreign, actor: user)
                                                .save!(contact_id: person.id, personal_tax_identifier: cpf, expected_revision: 0)
    expect(second.lookup_digest).not_to eq(first.lookup_digest)
    expect(first.reload.contact_id).to eq(contact.id)
  end

  it 'does not reuse request query-cache permissions after a real role revocation during decryption' do
    writer.save!(contact_id: contact.id, personal_tax_identifier: cpf, expected_revision: 0)
    agent = create(:user, account: account, role: :agent)
    restricted = create(:custom_role, account: account, permissions: [])
    member = account.account_users.find_by!(user: agent)
    allow(JrcCustomers::SigningIdentity).to receive(:find_by).and_wrap_original do |lookup, **arguments|
      record = lookup.call(**arguments)
      allow(record).to receive(:personal_tax_identifier).and_wrap_original do |original|
        value = original.call
        # A real database change without Rails invalidating this request's cache,
        # matching the stale-cache effect of a concurrent administrative change.
        database = ActiveRecord::Base.connection
        database.enable_query_cache!
        AccountUser.find_by(account_id: account.id, user_id: agent.id)
        database.raw_connection.exec("UPDATE account_users SET custom_role_id=#{restricted.id} WHERE id=#{member.id}")
        value
      end
      record
    end
    get url, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    expect(member.reload.custom_role_id).to eq(restricted.id)
    expect(response.body).not_to include(cpf)
  end

  it 'enforces the account and Contact pair in the database even when model validation is bypassed' do
    identity = writer.save!(contact_id: contact.id, personal_tax_identifier: cpf, expected_revision: 0)
    foreign = create(:contact)
    expect do
      JrcCustomers::SigningIdentity.transaction(requires_new: true) do
        ActiveRecord::Base.connection.execute("UPDATE jrc_customer_signing_identities SET contact_id=#{foreign.id} WHERE id=#{identity.id}")
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(identity.reload.contact_id).to eq(contact.id)
  end

  it 'does not disclose a matching contact in an uncovered internal company through duplicates or the generic merge endpoint' do
    issuer = account.master_companies.create!(name: 'TESTE SINTÉTICO — Operadora restrita', relationship_type: 'internal')
    hidden = create(:contact, account: account, company_id: issuer.id, phone_number: '+5511999999876')
    JrcCustomers::ContactPoint.create!(account: account, contact: contact, kind: 'phone', value: hidden.phone_number)
    get "#{root}/contacts/#{contact.id}/duplicates", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload'].pluck('id')).not_to include(hidden.id)
    post "/api/v1/accounts/#{account.id}/actions/contact_merge", params: { base_contact_id: contact.id, mergee_contact_id: hidden.id },
                                                                 headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(Contact.where(id: hidden.id)).to exist
  end
end
