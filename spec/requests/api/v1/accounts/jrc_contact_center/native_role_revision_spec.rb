require 'rails_helper'

RSpec.describe 'Call Center native role revisions', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let!(:headers) { actor.create_new_auth_token }
  let(:role) { create(:custom_role, account: account, permissions: ['jrc_contact_center_view'], description: 'Original') }
  let(:url) { "/api/v1/accounts/#{account.id}/custom_roles/#{role.id}" }
  let(:revision) { JrcContactCenter::RoleRevision.token(role) }

  before { account.enable_features!('jrc_contact_center', 'custom_roles') }

  it 'returns an additive revision and accepts an update against that exact version' do
    get url, headers: headers
    token = response.parsed_body.fetch('revision')
    expect(token).to match(/\A[0-9a-f]{64}\z/)
    patch url, headers: headers, params: { expected_revision: token, custom_role: { name: 'Reviewed' } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(role.reload.name).to eq('Reviewed')
    expect(response.parsed_body.fetch('revision')).not_to eq(token)
  end

  it 'rejects a stale form without changing newer data or recording a successful change' do
    token = revision
    role.update!(description: 'Newer session')
    audits = Enterprise::AuditLog.where(auditable: role).count
    patch url, headers: headers, params: { expected_revision: token, custom_role: { name: 'Stale' } }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body).to eq('error' => 'stale_role_revision')
    expect(role.reload.description).to eq('Newer session')
    expect(role.name).not_to eq('Stale')
    expect(Enterprise::AuditLog.where(auditable: role).count).to eq(audits)
  end

  it 'requires a nonblank version when the caller explicitly opts into preconditions' do
    patch url, headers: headers, params: { expected_revision: '', custom_role: { name: 'Invalid' } }, as: :json
    expect(response).to have_http_status(:precondition_required)
    expect(response.parsed_body).to eq('error' => 'role_revision_required')
    expect(role.reload.name).not_to eq('Invalid')
  end

  it 'rejects a malformed version without passing it to model assignment' do
    patch url, headers: headers, params: { expected_revision: { value: revision }, custom_role: { name: 'Invalid' } }, as: :json
    expect(response).to have_http_status(:precondition_required)
    expect(role.reload.name).not_to eq('Invalid')
  end

  it 'does not accept a token from a different native role' do
    foreign_role = create(:custom_role, account: create(:account), permissions: ['jrc_contact_center_view'])
    token = JrcContactCenter::RoleRevision.token(foreign_role)
    patch url, headers: headers, params: { expected_revision: token, custom_role: { name: 'Foreign version' } }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(role.reload.name).not_to eq('Foreign version')
  end

  it 'keeps native clients without preconditions compatible and still enforces the GrantGuard' do
    patch url, headers: headers, params: { custom_role: { name: 'Legacy client' } }, as: :json
    expect(response).to have_http_status(:ok)
    patch url, headers: headers, params: { custom_role: { permissions: %w[jrc_contact_center_view jrc_contact_center_publish] } }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(role.reload.permissions).to eq(['jrc_contact_center_view'])
  end

  it 'allows explicit re-review against the freshly loaded revision after a conflict' do
    token = revision
    role.update!(description: 'Newer session')
    patch url, headers: headers, params: { expected_revision: token, custom_role: { description: 'Reviewed draft' } }, as: :json
    expect(response).to have_http_status(:conflict)
    get url, headers: headers
    current = response.parsed_body.fetch('revision')
    patch url, headers: headers, params: { expected_revision: current, custom_role: { description: 'Reviewed draft' } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(role.reload.description).to eq('Reviewed draft')
  end
end
