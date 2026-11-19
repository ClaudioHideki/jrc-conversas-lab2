require 'rails_helper'

RSpec.describe 'Call Center form revisions in native configuration audit', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:headers) { actor.create_new_auth_token }
  let(:role) do
    create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_configure jrc_contact_center_audit])
  end
  let(:context) { { account: account, account_user: member, user: actor } }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center" }
  let(:input) do
    JrcContactCenter::AcwFormInput.new(
      name: 'SYNTHETIC private form name', description: 'SYNTHETIC private schema description', status: 'active',
      definition: { 'fields' => [{ 'key' => 'detail', 'label' => 'SYNTHETIC private label', 'type' => 'text', 'required' => true }] },
      request_id: SecureRandom.uuid, expected_revision: 0
    )
  end
  let(:entry) { JrcContactCenter::AcwFormWrite.new(context: context).call(input: input) }
  let(:audit) { Audited.audit_class.find_by!(auditable: entry[:version]) }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
    member.update!(custom_role: role)
  end

  it 'reuses the native audit detail with only immutable revision metadata and no private definition' do
    get "#{base}/configuration_audits/#{audit.id}", headers: headers
    expect(response).to have_http_status(:ok)
    item = response.parsed_body.fetch('item')
    expect(item).to include('resource_type' => 'acw_form_revision', 'resource_id' => entry[:version].id)
    expect(item.fetch('after').keys).to contain_exactly('revision', 'status', 'integrity_sha256')
    expect(item.fetch('omitted_fields')).to eq(%w[name description definition])
    expect(response.body).not_to include(actor.email, 'SYNTHETIC private form name',
                                         'SYNTHETIC private schema description', 'SYNTHETIC private label')
    expect(response.headers['Cache-Control']).to eq('no-store')
  end

  it 'filters the exact native revision without mixing accounts or unrelated configuration types' do
    get "#{base}/configuration_audits", headers: headers,
                                        params: { resource_type: 'acw_form_revision', resource_id: entry[:version].id, history: true }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([audit.id])
    expect(response.parsed_body.fetch('items').pluck('resource_type')).to eq(['acw_form_revision'])
  end

  it 'does not expose the new comment through the ordinary native audit relation after permission revocation' do
    audit
    role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_configure])
    get "#{base}/configuration_audits/#{audit.id}", headers: headers
    expect(response).to have_http_status(:unauthorized)
    member.reload # Match the fresh native controller context after the role change.
    relation = Audited.audit_class.where(associated: account)
    visible = JrcContactCenter::ConfigurationAuditScope.protect_native_list(relation, context)
    expect(visible.where(id: audit.id)).not_to exist
    expect(JrcContactCenter::ConfigurationAudit::COMMENTS).to include(JrcContactCenter::ConfigurationAudit::ACW_FORM_COMMENT)
  end

  it 'preserves independent audit authority without granting global form editing' do
    audit
    role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_audit])
    get "#{base}/configuration_audits/#{audit.id}", headers: headers
    expect(response).to have_http_status(:ok)
    get "#{base}/acw_forms", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'does not let limited business-unit coverage retrieve a global configuration revision' do
    audit
    company = account.master_companies.create!(name: 'SYNTHETIC issuer', relationship_type: 'internal')
    unit = JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: 'SYNTHETIC unit', code: 'SYNTHETIC')
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'BUSINESS_UNIT', company: company,
                                     business_unit: unit, active: true, structure_managed: true)
    get "#{base}/configuration_audits/#{audit.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    get "#{base}/configuration_audits", headers: headers,
                                        params: { resource_type: 'acw_form_revision', resource_id: entry[:version].id, history: true }
    expect(response.parsed_body.fetch('items')).to be_empty
  end

  it 'keeps an ordinary audit untouched while hiding unauthorized form metadata' do
    audit
    ordinary = Audited.audit_class.create!(auditable: account, associated: account, user: actor, action: 'update',
                                           audited_changes: { 'name' => %w[SYNTHETIC BEFORE] }, comment: 'SYNTHETIC ordinary module')
    role.update!(permissions: %w[jrc_contact_center_view])
    member.reload # The native audit controller rebuilds membership for every request.
    relation = JrcContactCenter::ConfigurationAuditScope.protect_native_list(Audited.audit_class.where(associated: account), context)
    expect(relation.where(id: ordinary.id)).to exist
    expect(relation.where(id: audit.id)).not_to exist
  end
end
