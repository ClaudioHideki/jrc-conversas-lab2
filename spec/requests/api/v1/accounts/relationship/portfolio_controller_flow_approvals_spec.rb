require 'rails_helper'

RSpec.describe Api::V1::Accounts::Relationship::PortfolioController, type: :request do
  include_context 'with a published relationship Flow'
  let(:node_definitions) { [['start', {}], ['note', { 'text' => 'Explicit request approval' }], ['end', {}]] }

  def request_preview
    version
    configuration
    post "/api/v1/accounts/#{sd_account.id}/relationship/playbook_preview",
         params: { id: book.id, assignment_id: assignment.id, source_key: source_key, playbook: book.snapshot },
         headers: sd_user.create_new_auth_token, as: :json
    response.parsed_body
  end

  def run_payload(preview)
    reviewed = preview.fetch('steps').first
    { operation: 'playbook', ids: [assignment.id], playbook_id: book.id, request_id: 'approved-request', source_key: source_key,
      flow_approvals: { reviewed.fetch('step_key') => reviewed.fetch('approval_token') } }
  end

  it 'runs only a published reviewed flow and reads the real execution result back through the authorized endpoint' do
    preview = request_preview
    expect(response).to have_http_status(:ok)
    expect(preview.fetch('steps').first.fetch('approval_token')).to be_present
    post "/api/v1/accounts/#{sd_account.id}/relationship/portfolio/batch", params: run_payload(preview),
                                                                           headers: sd_user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(JrcFlowRun.where(flow: flow).count).to eq(1)
    get "/api/v1/accounts/#{sd_account.id}/relationship/playbook_executions", headers: sd_user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    result = response.parsed_body.fetch('payload').first
    expect(result.fetch('snapshot').fetch('results').first).to include('resource_type' => 'JrcFlowRun', 'state' => 'completed')
    expect(result.to_json).not_to include(preview.fetch('steps').first.fetch('approval_token'))
  end

  it 'rejects a different full source key before any run is created' do
    preview = request_preview
    post "/api/v1/accounts/#{sd_account.id}/relationship/portfolio/batch", params: run_payload(preview).merge(source_key: 'altered-origin'),
                                                                           headers: sd_user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcFlowRun).not_to exist
    expect(JrcRelationship::PlaybookExecution).not_to exist
  end
end
