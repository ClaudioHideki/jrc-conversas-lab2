require 'rails_helper'

RSpec.describe 'Reviewed customer import entry', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:file) { Rack::Test::UploadedFile.new(StringIO.new("name,email\nPerson,person@example.test\n"), 'text/csv', original_filename: 'contacts.csv') }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/contacts/import" }

  it 'requires review instead of silently enqueuing an unscoped legacy import when the master is enabled' do
    account.enable_features!('jrc_customer_master')
    expect do
      post endpoint, headers: actor.create_new_auth_token, params: { import_file: file }
    end.not_to change(DataImport, :count)
    expect(response).to have_http_status(:conflict)
    expected = { 'code' => 'REVIEW_REQUIRED', 'review_path' => "/app/accounts/#{account.id}/customers/imports?kind=contacts" }
    expect(response.parsed_body).to include(expected)
    expect(account.contacts.count).to eq(0)
  end

  it 'preserves the existing native endpoint and job contract for accounts without the master feature' do
    account.disable_features!('jrc_customer_master')
    expect do
      post endpoint, headers: actor.create_new_auth_token, params: { import_file: file }
    end.to change(DataImport, :count).by(1)
    expect(response).to have_http_status(:ok)
    expect(DataImport.last).to be_legacy_contacts_csv_import
    expect(DataImport.last.import_file).to be_attached
    expect(DataImportJob).to have_been_enqueued.with(DataImport.last)
  end

  it 'retains the native permission denial before revealing the review destination' do
    account.enable_features!('jrc_customer_master')
    AccountUser.find_by!(account: account, user: actor).update!(role: :agent)
    post endpoint, headers: actor.create_new_auth_token, params: { import_file: file }
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).not_to have_key('review_path')
  end
end
