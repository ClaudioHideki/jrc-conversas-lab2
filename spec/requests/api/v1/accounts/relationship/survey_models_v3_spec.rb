# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'Service Desk six-step survey model API', type: :request do
  include_context 'Service Desk survey models V3'

  def create_draft(payload = survey_payload)
    post survey_url, params: { payload: payload }, headers: survey_headers, as: :json
    expect(response).to have_http_status(:created)
    response.parsed_body
  end

  it 'saves an incomplete draft without publishing or enrolling a survey' do
    data = survey_payload.deep_dup.merge('name' => '', 'questions' => [])
    expect { create_draft(data) }.not_to change(JrcRelationship::SurveyDefinition, :count)
    expect(JrcRelationship::Survey.where(account: sd_account)).to be_empty
    id = response.parsed_body.fetch('id')
    get "#{survey_url}/#{id}", headers: survey_headers
    expect(response.parsed_body.fetch('payload')).to eq(data)
  end

  it 'rejects publication with field and step errors, with no definition allocated' do
    row = create_draft(survey_payload.deep_dup.merge('name' => ''))
    expect do
      post "#{survey_url}/#{row['id']}/publish", params: { lock_version: row['lock_version'], request_key: SecureRandom.uuid }, headers: survey_headers, as: :json
    end.not_to change(JrcRelationship::SurveyDefinition, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('errors')).to include(hash_including('step' => 0, 'field' => 'name'))
  end

  it 'publishes definition and rule together and confirms through an independent GET without a send' do
    row = create_draft
    message_count, survey_count = Message.count, JrcRelationship::Survey.count
    key = SecureRandom.uuid
    post "#{survey_url}/#{row['id']}/publish", params: { lock_version: row['lock_version'], request_key: key }, headers: survey_headers, as: :json
    expect(response).to have_http_status(:ok)
    get "#{survey_url}/#{row['id']}", headers: survey_headers
    expect(response.parsed_body).to include('active' => true, 'changed' => false, 'publication_key' => key)
    definition = JrcRelationship::SurveyDefinition.find(response.parsed_body.fetch('definition_id'))
    expect(definition.settings.dig('service_desk_model', 'unit_id')).to eq(sd_unit.id)
    expect(JrcRelationship::SurveyRule.find_by!(definition: definition).matchers).to include('unit_id' => sd_unit.id)
    expect(Message.count).to eq(message_count)
    expect(JrcRelationship::Survey.count).to eq(survey_count)
  end

  it 'replays a publication key without another immutable version or side effect' do
    row = create_draft
    request = { lock_version: row['lock_version'], request_key: SecureRandom.uuid }
    post "#{survey_url}/#{row['id']}/publish", params: request, headers: survey_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect do
      post "#{survey_url}/#{row['id']}/publish", params: request, headers: survey_headers, as: :json
    end.not_to change(JrcRelationship::SurveyVersion, :count)
    expect(response).to have_http_status(:ok)
  end

  it 'does not change the published version while saving a new draft' do
    draft = publish_survey_model
    previous = draft.definition.snapshot.deep_dup
    patch "#{survey_url}/#{draft.id}", params: { lock_version: draft.lock_version, payload: survey_payload.merge('name' => 'Next draft') }, headers: survey_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['changed']).to be(true)
    expect(draft.definition.reload.snapshot).to eq(previous)
  end

  it 'returns a conflict for concurrent draft writes without losing the successful write' do
    row = create_draft
    patch "#{survey_url}/#{row['id']}", params: { lock_version: row['lock_version'], payload: survey_payload.merge('name' => 'First writer') }, headers: survey_headers, as: :json
    expect(response).to have_http_status(:ok)
    patch "#{survey_url}/#{row['id']}", params: { lock_version: row['lock_version'], payload: survey_payload.merge('name' => 'Stale writer') }, headers: survey_headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(JrcRelationship::SurveyModelDraft.find(row['id']).payload['name']).to eq('First writer')
  end

  it 'scopes a stable code by native unit and does not overwrite another unit' do
    first = create_draft
    second = create_draft(survey_payload.merge('unit_id' => sd_other_unit.id))
    expect(second['id']).not_to eq(first['id'])
    get survey_url, params: { unit_id: sd_unit.id }, headers: survey_headers
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([first['id']])
  end

  it 'denies a foreign unit without disclosing its configuration' do
    post survey_url, params: { payload: survey_payload.merge('unit_id' => sd_foreign_unit.id, 'operator_id' => sd_foreign_operator.id) }, headers: survey_headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(JrcRelationship::SurveyModelDraft.where(account: sd_account)).to be_empty
  end

  it 'does not grant model publication to an ordinary agent' do
    draft = publish_survey_model
    sd_account_user.update!(role: :agent)
    post "#{survey_url}/#{draft.id}/publish", params: { lock_version: draft.lock_version, request_key: SecureRandom.uuid }, headers: survey_headers, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'duplicates into an inactive unregistered draft without changing the live model' do
    draft = publish_survey_model
    post "#{survey_url}/#{draft.id}/duplicate", headers: survey_headers, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include('active' => false, 'definition_id' => nil)
    expect(response.parsed_body.dig('payload', 'active')).to be(false)
    expect(draft.definition.reload.status).to eq('active')
  end

  it 'deactivates the definition/rules through native versioning and preserves previous versions' do
    draft = publish_survey_model
    old_version = draft.definition.version
    post "#{survey_url}/#{draft.id}/deactivate", params: { lock_version: draft.lock_version }, headers: survey_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(draft.definition.reload.status).to eq('archived')
    expect(JrcRelationship::SurveyRule.where(definition: draft.definition).pluck(:active)).to eq([false])
    expect(JrcRelationship::SurveyVersion.where(entity_type: draft.definition.class.name, entity_id: draft.definition_id, version: old_version)).to exist
  end

  it 'blocks editing a managed model through the legacy administration endpoint' do
    draft = publish_survey_model
    patch "/api/v1/accounts/#{sd_account.id}/relationship/survey_administration/definitions/#{draft.definition_id}",
      params: { record: { name: 'Bypass', version: draft.definition.version } }, headers: survey_headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(draft.definition.reload.name).to eq('Synthetic feedback')
  end
end
