require 'rails_helper'

RSpec.describe 'Approval catalog draft import', type: :request, approval_core: true do
  let(:scope) { approval_scope }
  let(:author) { approval_actor(scope) }
  let(:url) { "/api/v1/accounts/#{scope[:account].id}/approvals/policies/import" }
  let(:headers) { author.user.create_new_auth_token }
  let(:seed) do
    { schema_version: '1.0', activate: false, tenant: 'RESOLVER_NO_AMBIENTE',
      people: [{ full_name: 'Pessoa Sintética', role: 'Área de teste' }],
      approval_rules: [{ code: 'SYNTHETIC_RULE_V1', module: 'Teste', title: 'Revisão sintética', enabled: false,
                         workflow_state: 'draft', approver_user_ids: [], self_approval_allowed: false }] }
  end
  let(:input) do
    { document: seed.to_json, format: 'json', mappings: { 'SYNTHETIC_RULE_V1' => 'synthetic.review' }, people_mappings: {},
      issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id, dry_run: true }
  end

  it 'previews without writes or authority grants, retaining unresolved people' do
    expect { post url, params: { catalog_import: input }, headers: headers, as: :json }.not_to change(JrcApprovals::Policy, :count)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['people'].first).to include('status' => 'pending_identity', 'approval_authority_granted' => false)
    expect(response.parsed_body).to include('activated' => false, 'requests_created' => 0)
  end

  it 'creates inactive drafts transactionally, replays the same intent and preserves existing codes' do
    post url, params: { catalog_import: input }, headers: headers, as: :json
    digest = response.parsed_body.fetch('plan_digest')
    apply = input.merge(dry_run: false, confirmed: true, idempotency_key: 'synthetic-import-1', expected_digest: digest)
    2.times { post url, params: { catalog_import: apply }, headers: headers, as: :json; expect(response).to have_http_status(:ok) }
    record = JrcApprovals::Policy.find_by!(account_id: scope[:account].id, code: 'SYNTHETIC_RULE_V1')
    expect(record.attributes).to include('state' => 'draft', 'enabled' => false, 'current_version_id' => nil)
    expect(record.draft_definition).to have_key('catalog_import')
    expect(JrcApprovals::Request.count).to eq(0)
    post url, params: { catalog_import: input }, headers: headers, as: :json
    expect(response.parsed_body['rows'].first).to include('action' => 'preserved', 'policy_id' => record.id)
  end

  it 'does not invent a native adapter or assign approvers from suggested names' do
    post url, params: { catalog_import: input.merge(mappings: {}) }, headers: headers, as: :json
    expect(response.parsed_body['rows'].first['action']).to eq('pending_mapping')
    expect(JrcApprovals::Policy.count).to eq(0)
    post url, params: { catalog_import: input.merge(mappings: { 'SYNTHETIC_RULE_V1' => 'unknown.event' }) }, headers: headers, as: :json
    expect(response.parsed_body['rows'].first['action']).to eq('pending_adapter')
  end

  it 'blocks activation flags, supplied approvers and foreign tenant declarations' do
    [seed.merge(activate: true), seed.merge(tenant: 'foreign-account'),
     seed.merge(approval_rules: [seed[:approval_rules].first.merge(approver_user_ids: [author.user_id])])].each do |invalid|
      post url, params: { catalog_import: input.merge(document: invalid.to_json) }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it 'rejects foreign-account identities instead of resolving by name' do
    outsider = create(:user)
    post url, params: { catalog_import: input.merge(people_mappings: { 'Pessoa Sintética' => outsider.id }) }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'requires a current authorized unit and denies another account' do
    other = approval_scope(account: scope[:account])
    post url, params: { catalog_import: input.merge(issuer_company_id: other[:company].id, business_unit_id: other[:unit].id) }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    outsider = approval_actor(approval_scope)
    post url, params: { catalog_import: input }, headers: outsider.user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects stale previews and rolls back a batch with duplicate native events' do
    post url, params: { catalog_import: input.merge(dry_run: false, confirmed: true, idempotency_key: 'stale-import', expected_digest: 'stale') }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(JrcApprovals::Policy.count).to eq(0)
    second = seed[:approval_rules].first.merge(code: 'SECOND_RULE_V1')
    post url, params: { catalog_import: input.merge(document: seed.merge(approval_rules: [seed[:approval_rules].first, second]).to_json, mappings: input[:mappings].merge('SECOND_RULE_V1' => 'synthetic.review')) }, headers: headers, as: :json
    expect(response.parsed_body['rows'].map { |row| row['action'] }).to eq(%w[conflict conflict])
  end

  it 'evaluates a 20-code CSV and leaves every unmapped row pending' do
    csv = "codigo;modulo;finalidade;estado_importacao\n" + 20.times.map { |i| "SYNTHETIC_#{i};Teste;Finalidade #{i};RASCUNHO_INATIVO\n" }.join
    post url, params: { catalog_import: input.merge(document: csv, format: 'csv', mappings: {}) }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['counts']).to eq('pending_mapping' => 20)
  end
end
