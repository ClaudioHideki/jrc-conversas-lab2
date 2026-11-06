require 'rails_helper'

RSpec.describe 'Native playbook history and controlled restoration', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship/playbooks" }
  let(:fields) do
    { name: 'Synthetic original book', trigger_kind: 'health', active: false, conditions: [],
      steps: [{ kind: 'activity', title: 'Original native activity', after_days: 0, step_key: 'original' }] }
  end
  let(:book) { JrcRelationship::Playbook.create!(fields.merge(account: account)) }
  let(:source) { book.versions.create!(account: account, actor: actor, version: 1, payload: book.snapshot) }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'preserves successive native API edits and immutable original definitions before restoring through the same writer' do
    post base, headers: headers, as: :json, params: { playbook: fields }
    expect(response).to have_http_status(:ok)
    record = JrcRelationship::Playbook.find(response.parsed_body.fetch('id'))
    original = record.versions.find_by!(version: 1).attributes
    allocation = JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account))
    execution = JrcRelationship::PlaybookExecution.create!(account: account, assignment: allocation, playbook: record, actor: actor,
                                                           version: 1, source_key: 'synthetic-historical-origin', execution_key: SecureRandom.hex(32),
                                                           snapshot: record.snapshot, step_source_keys: [])
    original_execution = execution.attributes
    [1, 2].each do |version|
      patch "#{base}/#{record.id}", headers: headers, as: :json,
                                    params: { playbook: fields.merge(name: "Synthetic iteration #{version}", version: version) }
      expect(response).to have_http_status(:ok), response.body
    end
    post "#{base}/#{record.id}/restore", headers: headers, as: :json,
                                         params: { version: 3, source_version: 1, reason: 'Reviewed original definition' }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body).to eq('id' => record.id, 'version' => 4, 'restored_from_version' => 1)
    expect([record.reload.name, record.active?, record.versions.find_by!(version: 1).attributes, execution.reload.attributes])
      .to eq([fields.fetch(:name), false, original, original_execution])
    expect(record.versions.pluck(:version).sort).to eq([1, 2, 3, 4])
    expect(JrcCrm::AuditEvent.order(:id).last.to_value).to include('restored_from_version' => 1, 'reason' => 'Reviewed original definition')
  end

  it 'rejects stale restoration and duplicate retry without changing the saved definition or old history' do
    source
    book.update!(name: 'Synthetic current definition', version: 2)
    post "#{base}/#{book.id}/restore", headers: headers, as: :json, params: { version: 3, source_version: 1, reason: 'Stale current version' }
    expect(response).to have_http_status(:conflict)
    expect([book.reload.version, book.name, book.versions.count]).to eq([2, 'Synthetic current definition', 1])
    post "#{base}/#{book.id}/restore", headers: headers, as: :json, params: { version: 2, source_version: 1, reason: 'Confirmed version' }
    expect(response).to have_http_status(:ok)
    before = JrcCrm::AuditEvent.count
    post "#{base}/#{book.id}/restore", headers: headers, as: :json, params: { version: 2, source_version: 1, reason: 'Confirmed version' }
    expect(response).to have_http_status(:conflict)
    expect([book.reload.version, JrcCrm::AuditEvent.count]).to eq([3, before])
  end

  it 'does not use caller fields as a historical definition or accept foreign playbooks' do
    source
    book.update!(version: 2)
    post "#{base}/#{book.id}/restore", headers: headers, as: :json, params: {
      version: 2, source_version: 1, reason: 'Native source only', playbook: fields.merge(name: 'Caller replacement must be ignored')
    }
    expect(response).to have_http_status(:ok)
    expect(book.reload.name).to eq(fields.fetch(:name))
    foreign = JrcRelationship::Playbook.create!(fields.merge(account: create(:account)))
    post "#{base}/#{foreign.id}/restore", headers: headers, as: :json, params: { version: 2, source_version: 1, reason: 'Forbidden cross tenant' }
    expect(response).to have_http_status(:not_found)
    expect(foreign.reload.version).to eq(1)
  end

  it 'retains native configure permission and rejects malformed restoration versions or absent reason' do
    source
    book.update!(version: 2)
    viewer = create(:user, account: account, role: :agent)
    post "#{base}/#{book.id}/restore", headers: viewer.create_new_auth_token, as: :json,
                                       params: { version: 2, source_version: 1, reason: 'Not authorized' }
    expect(response).to have_http_status(:forbidden)
    input = { version: 2, source_version: 1, reason: 'Reviewed' }
    [{ version: '2' }, { source_version: [] }, { source_version: 2 }, { reason: '' }].each do |invalid|
      post "#{base}/#{book.id}/restore", headers: headers, as: :json, params: input.merge(invalid)
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(book.reload.version).to eq(2)
  end

  it 'rejects an incomplete legacy snapshot instead of silently combining it with the current definition' do
    book.versions.create!(account: account, actor: actor, version: 1, payload: { name: 'Incomplete old snapshot' })
    book.update!(name: 'Preserved current definition', version: 2)
    post "#{base}/#{book.id}/restore", headers: headers, as: :json, params: { version: 2, source_version: 1, reason: 'Must not partially restore' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect([book.reload.version, book.name, book.versions.count]).to eq([2, 'Preserved current definition', 1])
  end

  it 'reuses current native Flow pin validation and rolls back restoration when the published definition changed' do
    with_modified_env(JRC_FLOWS_ENABLED: 'true', JRC_FLOWS_EXTERNAL_BETA: 'false') do
      account.enable_features!('jrc_flows')
      contact = create(:contact, account: account)
      conversation = create(:conversation, account: account, contact: contact, inbox: create(:channel_api, account: account).inbox)
      graph = { nodes: [{ id: 'start', type: 'start', label: 'Synthetic start', position: { x: 0, y: 0 }, data: {} },
                        { id: 'end', type: 'end', label: 'Synthetic end', position: { x: 100, y: 0 }, data: {} }],
                edges: [{ id: 'next', source: 'start', target: 'end', port: 'next' }] }
      flow = JrcFlow.create!(account: account, created_by: actor, name: 'Synthetic pinned restore flow', kind: 'workflow',
                             status: 'active', graph: graph,
                             settings: { trigger: 'manual', inbox_ids: [conversation.inbox_id], days: [1, 2, 3, 4, 5] })
      step = { kind: 'flow', title: 'Historical native flow', after_days: 0, step_key: 'historical', flow_id: flow.id,
               flow_lock_version: flow.lock_version, flow_digest: JrcRelationship::PlaybookFlow.definition_digest(flow),
               contact_id: contact.id, conversation_id: conversation.id }
      record = JrcRelationship::Playbook.create!(fields.merge(account: account, steps: [step]))
      original = record.versions.create!(account: account, actor: actor, version: 1, payload: record.snapshot)
      record.update!(version: 2, name: 'Synthetic current flow definition')
      flow.update!(name: 'Synthetic changed published flow')
      before = [JrcFlowRun.count, Message.count, JrcCrm::AuditEvent.count]
      post "#{base}/#{record.id}/restore", headers: headers, as: :json, params: { version: 2, source_version: 1, reason: 'Must not repin old flow' }
      expect(response).to have_http_status(:unprocessable_entity), response.body
      expect([record.reload.version, record.versions.count, record.steps]).to eq([2, 1, [step.as_json]])
      expect([JrcFlowRun.count, Message.count, JrcCrm::AuditEvent.count]).to eq(before)
      expect(original.reload.payload.fetch('steps').first.fetch('flow_lock_version')).to be < flow.lock_version
    end
  end
end
