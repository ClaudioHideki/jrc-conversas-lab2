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
end
