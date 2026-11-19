require 'rails_helper'

RSpec.describe 'Call Center immutable ACW form library', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:headers) { actor.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center/acw_forms" }
  let(:definition) { { 'fields' => [{ 'key' => 'detail', 'label' => 'SYNTHETIC field', 'type' => 'text', 'required' => true }] } }
  let(:values) do
    { name: 'SYNTHETIC form', description: 'SYNTHETIC private schema description', status: 'active', definition: definition,
      request_id: SecureRandom.uuid, expected_revision: 0 }
  end

  let(:form_audits) do
    Audited.audit_class.where(associated: account, auditable_type: 'JrcContactCenter::AcwFormVersion')
  end

  before { account.enable_features!('jrc_contact_center') }

  it 'creates and reloads an owned version with real persistence and noncacheable account identity' do
    post base, headers: headers, params: { acw_form: values }, as: :json
    expect(response).to have_http_status(:created)
    expect(response.headers['Cache-Control']).to include('no-store')
    item = response.parsed_body.fetch('item')
    expect(item).to include('name' => values[:name], 'revision' => 1, 'definition' => definition, 'provider_applied' => false)
    get "#{base}/#{item.fetch('id')}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('account_id')).to eq(account.id.to_s)
    expect(response.parsed_body.fetch('item')).to eq(item)
  end

  it 'keeps append-only version history and detects stale updates instead of overwriting data' do
    post base, headers: headers, params: { acw_form: values }, as: :json
    id = response.parsed_body.fetch('item').fetch('id')
    changed = values.merge(name: 'SYNTHETIC next', expected_revision: 1, request_id: SecureRandom.uuid)
    patch "#{base}/#{id}", headers: headers, params: { acw_form: changed }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('latest_revision')).to eq(2)
    patch "#{base}/#{id}", headers: headers, params: { acw_form: changed.merge(request_id: SecureRandom.uuid) }, as: :json
    expect(response).to have_http_status(:conflict)
    get "#{base}/#{id}/versions/1", headers: headers
    expect(response.parsed_body.fetch('item')).to include('name' => values[:name], 'revision' => 1)
    get "#{base}/#{id}/versions", headers: headers
    expect(response.parsed_body.fetch('items').pluck('revision')).to eq([2, 1])
    expect(response.parsed_body.fetch('items').flat_map(&:keys)).not_to include('definition')
  end

  it 'replays a completed create request without duplicating a form, version or native audit' do
    post base, headers: headers, params: { acw_form: values }, as: :json
    first = response.parsed_body.fetch('item')
    counts = [JrcContactCenter::AcwFormTemplate.where(account: account).count, JrcContactCenter::AcwFormVersion.where(account: account).count,
              form_audits.count]
    post base, headers: headers, params: { acw_form: values }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('item' => first, 'replayed' => true, 'latest_revision' => 1)
    expect([JrcContactCenter::AcwFormTemplate.where(account: account).count,
            JrcContactCenter::AcwFormVersion.where(account: account).count, form_audits.count]).to eq(counts)
  end

  it 'requires an explicit revision and rejects malformed or authority-looking request data' do
    post base, headers: headers, params: { acw_form: values.except(:expected_revision) }, as: :json
    expect(response).to have_http_status(:precondition_required)
    post base, headers: headers, params: { acw_form: [values] }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post base, headers: headers, params: { acw_form: values.merge(account_id: create(:account).id) }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::AcwFormTemplate.where(account: account)).to be_empty
  end

  it 'does not turn GROUP corporate coverage into module configuration permission' do
    account.enable_features!('custom_roles')
    role = create(:custom_role, account: account, permissions: ['jrc_contact_center_view'])
    member.update!(custom_role: role)
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'GROUP', active: true, structure_managed: true)
    post base, headers: headers, params: { acw_form: values }, as: :json
    expect(response).to have_http_status(:unauthorized)
    get base, headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::AcwFormTemplate.where(account: account)).to be_empty
  end

  it 'denies global library access after a previously authorized member loses eligibility' do
    post base, headers: headers, params: { acw_form: values }, as: :json
    id = response.parsed_body.fetch('item').fetch('id')
    JrcContactCenter::AccessGrant.find_by!(account_user: member).update!(eligible: false)
    get "#{base}/#{id}", headers: headers
    expect(response).to have_http_status(:unauthorized)
    patch "#{base}/#{id}", headers: headers, params: { acw_form: values }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::AcwFormVersion.where(account: account).count).to eq(1)
  end

  it 'never expands the catalogue account through list parameters or a guessed foreign form ID' do
    post base, headers: headers, params: { acw_form: values }, as: :json
    id = response.parsed_body.fetch('item').fetch('id')
    other_account = create(:account)
    other_account.enable_features!('jrc_contact_center')
    other = create(:user, :contact_center_eligible, account: other_account, role: :administrator)
    context = { account: other_account, account_user: other_account.account_users.find_by!(user: other), user: other }
    foreign = JrcContactCenter::AcwFormWrite.new(context: context).call(input: JrcContactCenter::AcwFormInput.new(**values))
    get base, headers: headers, params: { account_id: other_account.id }
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([id])
    get "#{base}/#{foreign[:form].id}", headers: headers
    expect(response).to have_http_status(:not_found)
    get "#{base}/#{foreign[:form].id}/versions/1", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'filters the entire incoming form envelope in loaded native Rails request logging' do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    result = filter.filter('acw_form' => values.deep_stringify_keys)
    expect(result.fetch('acw_form')).to eq('[FILTERED]')
    expect(result.to_json).not_to include('SYNTHETIC private schema description', 'SYNTHETIC field')
  end
end
