require 'rails_helper'

RSpec.describe 'Customer master import runs', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/customers/import_runs" }
  let(:runs) { JrcCustomers::ImportRuns.new(account: account, actor: actor) }
  let(:content) { "name,email\nImported,imported@example.test\n" }
  let(:run) { runs.create!(content: content, kind: 'contacts', filename: 'people.csv') }
  let(:mapping) { { name: 'contact.name', email: 'contact.email' } }
  let(:options) { { existing: 'update', confirmations: {} } }

  before { account.enable_features!('jrc_customer_master', 'companies') }

  it 'uploads and maps the source, then reviews it without writing native records' do
    file = Rack::Test::UploadedFile.new(StringIO.new(content), 'text/csv', original_filename: 'people.csv')
    post base, headers: headers, params: { kind: 'contacts', file: file }
    expect(response).to have_http_status(:created)
    data = response.parsed_body
    id = data.fetch('payload').fetch('id')
    expect(data.fetch('file').fetch('headers')).to eq(%w[name email])
    expect(data.fetch('column_mapping')).to eq(mapping.stringify_keys)
    expect(account.contacts.count).to eq(0)
    post "#{base}/#{id}/preview", headers: headers, params: { column_mapping: mapping, import_options: options }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('errors')).to be_empty
    expect(account.contacts.count).to eq(0)
  end

  it 'explicitly applies native records, reads their durable result and acknowledges retries without duplicate writes' do
    id = run.id
    post "#{base}/#{id}/preview", headers: headers, params: { column_mapping: mapping, import_options: options }, as: :json
    token = response.parsed_body.fetch('token')
    post "#{base}/#{id}/apply", headers: headers, params: { token: token, confirm: true }, as: :json
    expect(response.parsed_body.fetch('payload')).to include('status' => 'completed', 'processed_records' => 1)
    contact = account.contacts.find_by!(email: 'imported@example.test')
    get "#{base}/#{id}/rows", headers: headers, params: { per_page: 1 }
    expect(response.parsed_body.fetch('payload').first).to include('entity' => 'contact', 'record_id' => contact.id, 'action' => 'create')
    expect(response.parsed_body.fetch('meta')).to include('total' => 1, 'per_page' => 1)
    get "#{base}/#{id}", headers: headers
    expect(response.parsed_body.keys).to eq(['payload'])
    expect(response.headers['Cache-Control']).to include('no-store')
    post "#{base}/#{id}/apply", headers: headers, params: { token: token, confirm: true }, as: :json
    expect(account.contacts.count).to eq(1)
    expect(DataImport.find(id).items.count).to eq(1)
  end

  it 'retains native bulk permissions including Enterprise contact_manage without granting company access' do
    role = create(:custom_role, account: account, permissions: ['contact_manage'])
    AccountUser.find_by!(account: account, user: actor).update!(role: :agent, custom_role: role)
    get "#{base}/metadata", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('available_kinds')).to eq(['contacts'])
    get "#{base}/template", headers: headers, params: { kind: 'companies' }
    expect(response).to have_http_status(:unauthorized)
    get "#{base}/template", headers: headers, params: { kind: 'contacts' }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('name;email;phone_number')
    expect(response.headers['Content-Disposition']).to include('attachment')
    role.update!(permissions: ['conversation_manage'])
    get "#{base}/metadata", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'does not disclose another owner or account run even when the actor belongs to both accounts' do
    id = run.id
    other = create(:user, account: account, role: :administrator)
    get "#{base}/#{id}", headers: other.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    foreign = create(:account)
    foreign.enable_features!('jrc_customer_master')
    create(:account_user, account: foreign, user: actor, role: :administrator)
    %w[rows errors].each do |path|
      get "/api/v1/accounts/#{foreign.id}/customers/import_runs/#{id}/#{path}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
    AccountUser.find_by!(account: account, user: actor).update!(role: :agent)
    get "#{base}/#{id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'paginates only current actor history, caps page size and treats search wildcards literally' do
    3.times { |index| runs.create!(content: content, kind: 'contacts', filename: "people#{index}.csv") }
    other = create(:user, account: account, role: :administrator)
    JrcCustomers::ImportRuns.new(account: account, actor: other).create!(content: content, kind: 'contacts', filename: 'private.csv')
    get base, headers: headers, params: { per_page: 2, page: 1 }
    first = response.parsed_body
    expect(first.fetch('meta')).to include('total' => 3, 'per_page' => 2)
    get base, headers: headers, params: { per_page: 2, page: 2 }
    second = response.parsed_body.fetch('payload')
    expect(second.size).to eq(1)
    expect(first.fetch('payload').pluck('id') & second.pluck('id')).to be_empty
    get base, headers: headers, params: { per_page: 900 }
    expect(response.parsed_body.fetch('meta').fetch('per_page')).to eq(50)
    get base, headers: headers, params: { q: '%' }
    expect(response.parsed_body.fetch('payload')).to be_empty
    get base, headers: headers, params: { status: 'invented' }
    expect(response).to have_http_status(:bad_request)
  end

  it 'reports field errors for the latest review and exports a real CSV without original row values' do
    content.replace("name,email\nSecret name,invalid\n")
    post "#{base}/#{run.id}/preview", headers: headers, params: { column_mapping: mapping, import_options: options }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('token')).to be_nil
    get "#{base}/#{run.id}/errors", headers: headers, params: { per_page: 1 }
    error = response.parsed_body.fetch('payload').first
    expect(error).to include('line' => 2, 'entity' => 'contact', 'field' => 'email')
    get "#{base}/#{run.id}/errors.csv", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('registro;entidade;campo;codigo;erro', '2;contact;email;VALIDATION_FAILED;')
    expect(response.body).not_to include('Secret name')
    run.import_errors.create!(source_object_type: 'contact', source_object_id: '3', error_code: 'FORMULA', message: '=1+1',
                              details: { review_revision: 1, field: 'email', entity: 'contact' })
    get "#{base}/#{run.id}/errors.csv", headers: headers
    expect(response.body).to include("'=1+1")
  end

  it 'rejects missing mapping decisions, boolean coercion and stale signed plans without writing' do
    post "#{base}/#{run.id}/preview", headers: headers, params: { column_mapping: { name: 'contact.name' }, import_options: options }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post "#{base}/#{run.id}/preview", headers: headers, params: { column_mapping: mapping, import_options: options }, as: :json
    token = response.parsed_body.fetch('token')
    post "#{base}/#{run.id}/apply", headers: headers, params: { token: token, confirm: 'true' }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    create(:contact, account: account, email: 'imported@example.test')
    post "#{base}/#{run.id}/apply", headers: headers, params: { token: token, confirm: true }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('code')).to eq('REVIEW_REQUIRED')
    expect(run.items.count).to eq(0)
    expect(account.contacts.count).to eq(1)
  end
end
