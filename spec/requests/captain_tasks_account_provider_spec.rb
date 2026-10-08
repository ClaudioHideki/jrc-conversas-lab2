require 'rails_helper'

RSpec.describe 'Captain tasks account provider', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let!(:provider) do
    JrcAi::Provider.create!(account: account, name: 'Account AI', provider_type: 'openai',
                            api_key: 'test-account-one-key', default_model: 'gpt-4.1-mini', default_provider: true)
  end
  let(:headers) { user.create_new_auth_token }
  let(:params) { { content: 'Test draft', operation: 'fix_spelling_grammar' } }
  let(:url) { "/api/v1/accounts/#{account.id}/captain/tasks/rewrite" }

  before do
    account.enable_features!('captain_tasks')
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-global-key')
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'test-old-hook-key' })
  end

  it 'rejects a missing account provider with a controlled error and no alternate credential' do
    provider.destroy!
    JrcAi::Provider.create!(account: other_account, name: 'Other AI', provider_type: 'openai',
                            api_key: 'test-account-two-key', default_model: 'gpt-4.1-mini')
    expect(Llm::Config).not_to receive(:with_api_key)
    post url, params: params, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to include('error_code' => 'account_ai_not_configured')
    expect(response.body).not_to include('test-global-key', 'test-old-hook-key', 'test-account-two-key')
  end

  it 'rejects an invalid endpoint before any provider request' do
    provider.update!(base_url: 'https://unapproved.example.invalid/v1')
    expect(Llm::Config).not_to receive(:with_api_key)
    post url, params: params, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to include('error_code' => 'invalid_configuration')
  end

  it 'ignores browser-supplied provider, model and credentials and returns no secret' do
    context = instance_double(RubyLLM::Context)
    chat = instance_double(RubyLLM::Chat)
    message = instance_double(RubyLLM::Message, content: 'Fixed draft', input_tokens: 5, output_tokens: 3)
    expect(Llm::Config).to receive(:with_api_key).with('test-account-one-key', api_base: 'https://api.openai.com/v1').and_yield(context)
    expect(context).to receive(:chat).with(model: 'gpt-4.1-mini', provider: :openai, assume_model_exists: true).and_return(chat)
    allow(chat).to receive(:with_instructions)
    allow(chat).to receive(:ask).and_return(message)
    post url, params: params.merge(provider_id: 999, api_key: 'test-browser-key', model: 'foreign-model'), headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('message' => 'Fixed draft')
    expect(response.body).not_to include('test-account-one-key', 'test-browser-key', 'test-global-key', 'api_key')
    expect(account.jrc_ai_usage_events.last).to have_attributes(account_id: account.id, provider_id: provider.id, user_id: user.id)
  end

  it 'never serializes the stored provider key to the browser' do
    get "/api/v1/accounts/#{account.id}/jrc_ai/providers", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('test-account-one-key')
    expect(response.parsed_body.first).to include('api_key_configured' => true, 'masked_api_key' => provider.masked_api_key)
  end

  it 'rejects access to the other account before performing any AI request' do
    expect(Llm::Config).not_to receive(:with_api_key)
    post "/api/v1/accounts/#{other_account.id}/captain/tasks/rewrite", params: params, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
  end
end
