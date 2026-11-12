require 'rails_helper'

RSpec.describe 'Native playbook typed JSON input', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship/playbooks" }
  let(:fields) do
    { name: 'Synthetic conditional definition', trigger_kind: 'health', active: false,
      conditions: [{ field: 'health_score', operator: 'lt', value: 60 }],
      steps: [{ kind: 'activity', step_key: 'native', title: 'Native finite task', after_days: 0 }] }
  end
  let(:book) { JrcRelationship::Playbook.create!(fields.merge(account: account)) }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'does not silently turn a null condition into an unconditional saved automation' do
    book
    before = [book.attributes, JrcRelationship::PlaybookVersion.count, JrcCrm::AuditEvent.count]
    patch "#{base}/#{book.id}", headers: headers, as: :json, params: { playbook: fields.merge(version: 1, conditions: [nil]) }
    expect(response).to have_http_status(:unprocessable_entity)
    expect([book.reload.attributes, JrcRelationship::PlaybookVersion.count, JrcCrm::AuditEvent.count]).to eq(before)
  end

  it 'rejects mixed invalid step entries instead of dropping them and publishing an incomplete sequence' do
    before = [JrcRelationship::Playbook.count, JrcRelationship::PlaybookVersion.count, JrcCrm::AuditEvent.count]
    post base, headers: headers, as: :json, params: { playbook: fields.merge(steps: [*fields.fetch(:steps), nil]) }
    expect(response).to have_http_status(:unprocessable_entity)
    expect([JrcRelationship::Playbook.count, JrcRelationship::PlaybookVersion.count, JrcCrm::AuditEvent.count]).to eq(before)
  end

  it 'returns a controlled error for a collection in place of the playbook object' do
    post base, headers: headers, as: :json, params: { playbook: [fields] }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcRelationship::Playbook.where(account: account)).not_to exist
  end

  it 'retains valid empty conditions and the native strong-parameter field allowlists' do
    extra = fields.fetch(:steps).first.merge(account_id: -1, private_api_token: 'synthetic-must-not-be-stored')
    post base, headers: headers, as: :json, params: { playbook: fields.merge(account_id: -1, conditions: [], steps: [extra]) }
    expect(response).to have_http_status(:ok)
    row = JrcRelationship::Playbook.find(response.parsed_body.fetch('id'))
    expect([row.account_id, row.conditions, row.steps]).to eq([account.id, [], fields.fetch(:steps).as_json])
    expect(response.body).not_to include('synthetic-must-not-be-stored')
  end

  it 'retains native partial edits without substituting empty conditions when the field is absent' do
    patch "#{base}/#{book.id}", headers: headers, as: :json, params: { playbook: { version: 1, name: 'Native partial edit' } }
    expect(response).to have_http_status(:ok)
    expect([book.reload.name, book.version, book.conditions, book.steps])
      .to eq(['Native partial edit', 2, fields.fetch(:conditions).as_json, fields.fetch(:steps).as_json])
  end

  it 'rejects malformed collection shapes without changing the persisted definition' do
    book
    before = [book.attributes, JrcRelationship::PlaybookVersion.count, JrcCrm::AuditEvent.count]
    [{ conditions: nil }, { conditions: {} }, { conditions: [false] }, { steps: nil }, { steps: {} }, { steps: ['invalid'] }].each do |invalid|
      patch "#{base}/#{book.id}", headers: headers, as: :json, params: { playbook: invalid.merge(version: 1) }
      expect(response).to have_http_status(:unprocessable_entity)
      expect([book.reload.attributes, JrcRelationship::PlaybookVersion.count, JrcCrm::AuditEvent.count]).to eq(before)
    end
  end

  it 'preserves the existing form-encoded partial edit contract' do
    patch "#{base}/#{book.id}", headers: headers, params: { playbook: { version: 1, name: 'Native form edit' } }
    expect(response).to have_http_status(:ok)
    expect([book.reload.name, book.version, book.conditions, book.steps])
      .to eq(['Native form edit', 2, fields.fetch(:conditions).as_json, fields.fetch(:steps).as_json])
  end
end
