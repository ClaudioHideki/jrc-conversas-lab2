require 'rails_helper'

RSpec.describe 'Versioned native CRM activity editing', type: :request do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }
  let(:lead) { account.jrc_crm_leads.create!(owner: actor, contact: contact, name: 'Synthetic edit origin') }
  let(:activity) do
    account.jrc_crm_activities.create!(user: actor, lead: lead, contact: contact, title: 'Original commitment', activity_type: 'task',
                                       due_at: Time.utc(2026, 11, 6, 14, 30), description: 'Private original notes')
  end
  let(:url) { "/api/v1/accounts/#{account.id}/crm/activities/#{activity.id}" }
  let(:headers) { actor.create_new_auth_token }
  let(:version) { activity.updated_at.utc.iso8601(6) }

  before { account.enable_features!('jrc_crm') }

  it 'persists the original record in account local time with an exact source version and a minimized transactional audit' do
    get url, headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body).to include('edit_version' => version, 'due_at_local' => '2026-11-06T11:30:00',
                                            'time_zone' => 'America/Sao_Paulo')
    source = activity.attributes.slice('user_id', 'lead_id', 'activity_type', 'contact_id', 'account_id', 'metadata')
    patch url, headers: headers, params: { expected_version: version,
                                           activity: { title: 'Revised commitment', description: 'Private new notes',
                                                       due_at: '2026-11-07T10:15:12' } }
    expect(response).to have_http_status(:ok), response.body
    expect(activity.reload).to have_attributes(title: 'Revised commitment', due_at: Time.utc(2026, 11, 7, 13, 15, 12))
    expect(activity.attributes.slice(*source.keys)).to eq(source)
    audit = JrcCrm::AuditEvent.find_by!(account: account, resource_type: activity.class.name, resource_id: activity.id,
                                        event_type: 'activity_updated')
    expect(audit).to have_attributes(actor_id: actor.id, metadata: include('changed_fields' => array_including('title', 'description', 'due_at')))
    expect(audit.attributes.to_json).not_to include('Private original notes', 'Private new notes')
  end

  it 'rejects a stale microsecond version without overwriting the newer source or creating an edit audit' do
    stale = version
    activity.update!(title: 'Newer concurrent title', updated_at: activity.updated_at + Rational(1, 1_000_000))
    patch url, headers: headers, params: { expected_version: stale, activity: { title: 'Stale title', due_at: '2026-11-08T12:00' } }
    expect(response).to have_http_status(:conflict), response.body
    expect(activity.reload.title).to eq('Newer concurrent title')
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'activity_updated')).not_to exist
  end

  it 'retains all original fields when native validation rejects the edit and accepts legacy updates without an optional version' do
    before = activity.attributes.deep_dup
    patch url, headers: headers, params: { expected_version: version, activity: { title: '' } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(activity.reload.attributes).to eq(before)
    patch url, headers: headers, params: { activity: { title: 'Compatible native client' } }
    expect(response).to have_http_status(:ok)
    expect(activity.reload.title).to eq('Compatible native client')
  end

  it 'rolls back the source edit when its mandatory editor audit fails' do
    before = activity.attributes.deep_dup
    invalid_audit = JrcCrm::AuditEvent.new
    invalid_audit.errors.add(:base, 'Synthetic audit unavailable')
    allow(JrcCustomers::Audit).to receive(:record!).and_raise(ActiveRecord::RecordInvalid.new(invalid_audit))
    patch url, headers: headers, params: { expected_version: version, activity: { title: 'Must roll back' } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(activity.reload.attributes).to eq(before)
  end

  it 'enforces current native ownership, feature and tenant permissions rather than trusting the selected record ID or user parameter' do
    other = create(:user, account: account, role: :agent)
    patch url, headers: other.create_new_auth_token, params: { expected_version: version, activity: { title: 'Denied', user_id: other.id } }
    expect(response).to have_http_status(:not_found)
    outsider = create(:user, account: create(:account), role: :administrator)
    patch url, headers: outsider.create_new_auth_token, params: { expected_version: version, activity: { title: 'Denied' } }
    expect(response).to have_http_status(:unauthorized)
    account.disable_features!('jrc_crm')
    patch url, headers: headers, params: { expected_version: version, activity: { title: 'Denied' } }
    expect(response).to have_http_status(:forbidden)
    expect(activity.reload.title).to eq('Original commitment')
  end

  it 'rejects corporate-unit access outside the existing native coverage before editing' do
    company = account.master_companies.create!(name: 'Synthetic editor issuer', relationship_type: 'internal', tax_id: '11444777000161')
    units = Array.new(2) do |index|
      account.jrc_crm_business_units.create!(name: "Synthetic edit unit #{index}", code: SecureRandom.hex(6), company_id: company.id)
    end
    activity.update!(business_unit: units.last)
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: company, business_unit: units.first,
                                                active: true, structure_managed: true)
    patch url, headers: headers, params: { expected_version: version, activity: { title: 'Denied', business_unit_id: units.last.id } }
    expect(response).to have_http_status(:not_found)
    expect(activity.reload.title).to eq('Original commitment')
  end
end
