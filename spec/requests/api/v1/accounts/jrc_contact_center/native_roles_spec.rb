require 'rails_helper'

RSpec.describe 'Call Center native role boundaries', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:role) { create(:custom_role, account: account, permissions: ['jrc_contact_center_view']) }
  let(:url) { "/api/v1/accounts/#{account.id}/custom_roles/#{role.id}" }

  before { account.enable_features!('jrc_contact_center', 'custom_roles') }

  it 'returns not found for a foreign role without changing either Account' do
    foreign = create(:custom_role, account: create(:account), permissions: ['jrc_contact_center_view'])
    patch "/api/v1/accounts/#{account.id}/custom_roles/#{foreign.id}",
          headers: headers, params: { custom_role: { name: 'Forbidden' } }
    expect(response).to have_http_status(:not_found)
    expect(foreign.reload.name).not_to eq('Forbidden')
  end

  it 'preserves the role and audit history when an actor cannot grant a critical power' do
    role
    count = Enterprise::AuditLog.where(comment: 'JRC Call Center native capabilities', associated: account).count
    patch url, headers: headers, params: { custom_role: { permissions: %w[jrc_contact_center_view jrc_contact_center_publish] } }
    expect(response).to have_http_status(:unauthorized)
    expect(role.reload.permissions).to eq(['jrc_contact_center_view'])
    expect(Enterprise::AuditLog.where(comment: 'JRC Call Center native capabilities', associated: account).count).to eq(count)
  end

  it 'serializes the native update and permits removing an existing power without automatic grants' do
    role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_publish])
    queries = []
    subscription = ActiveSupport::Notifications.subscribe('sql.active_record') { |event| queries << event.payload[:sql] }
    patch url, headers: headers, params: { custom_role: { permissions: ['jrc_contact_center_view'] } }
    expect(response).to have_http_status(:success)
    expect(queries.grep(/custom_roles.*FOR UPDATE/)).not_to be_empty
    expect(role.reload.permissions).to eq(['jrc_contact_center_view'])
    expect(Enterprise::AuditLog.where(comment: 'JRC Call Center native capabilities', associated: account).last.user_id).to eq(actor.id)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription) if subscription
  end

  context 'with an administrator restricted to a corporate business unit' do
    let(:company) { account.master_companies.create!(name: 'SYNTHETIC issuer', relationship_type: 'internal') }
    let(:unit) { JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: 'SYNTHETIC unit', code: 'SYNTHETIC') }

    before do
      JrcCrm::UserBusinessUnit.create!(
        account: account, user: actor, scope: 'BUSINESS_UNIT', business_unit: unit,
        company: company, active: true, structure_managed: true
      )
    end

    it 'denies metadata changes to an Account-wide Call Center role' do
      patch url, headers: headers, params: { custom_role: { name: 'Forbidden' } }
      expect(response).to have_http_status(:unauthorized)
      expect(role.reload.name).not_to eq('Forbidden')
    end

    it 'denies removals and deletion without turning a restricted scope into global authority' do
      patch url, headers: headers, params: { custom_role: { permissions: [] } }
      expect(response).to have_http_status(:unauthorized)
      delete url, headers: headers
      expect(response).to have_http_status(:unauthorized)
      expect(role.reload.permissions).to eq(['jrc_contact_center_view'])
    end

    it 'denies creation of a global Call Center role through a direct API request' do
      expect do
        post "/api/v1/accounts/#{account.id}/custom_roles",
             headers: headers, params: { custom_role: { name: 'Forbidden', permissions: ['jrc_contact_center_view'] } }
      end.not_to change(CustomRole, :count)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'permits an explicitly configured synthetic Group authority to remove a power' do
      JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'GROUP', active: true, structure_managed: true)
      patch url, headers: headers, params: { custom_role: { permissions: [] } }
      expect(response).to have_http_status(:success)
      expect(role.reload.permissions).to eq([])
    end

    it 'preserves native editing of unrelated role capabilities' do
      other_role = create(:custom_role, account: account, permissions: ['contact_manage'])
      patch "/api/v1/accounts/#{account.id}/custom_roles/#{other_role.id}",
            headers: headers, params: { custom_role: { name: 'Native authority preserved' } }
      expect(response).to have_http_status(:success)
      expect(other_role.reload.name).to eq('Native authority preserved')
    end
  end
end
