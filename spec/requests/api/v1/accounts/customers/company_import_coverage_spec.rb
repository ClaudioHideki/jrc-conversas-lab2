require 'rails_helper'

RSpec.describe 'Customer CSV corporate coverage API', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:operator_a) { account.master_companies.create!(name: 'Synthetic API operator A', relationship_type: 'internal') }
  let(:operator_b) { account.master_companies.create!(name: 'Synthetic hidden API operator B', relationship_type: 'internal') }
  let(:unit) { account.jrc_crm_business_units.create!(name: 'Synthetic API A', code: SecureRandom.hex(8), company_id: operator_a.id) }
  let(:grant) do
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: operator_a, business_unit: unit,
                                                active: true, structure_managed: true)
  end
  let(:root) { "/api/v1/accounts/#{account.id}/customers/imports" }

  before do
    account.enable_features!('jrc_customer_master', 'jrc_crm')
    actor
    unit
    grant
  end

  it 'does not expose an uncovered issuer in the CSV preview even to an account administrator' do
    Tempfile.create(['synthetic-company-scope', '.csv']) do |file|
      file.write("id,name\n#{operator_b.id},Synthetic unauthorized request\n")
      file.flush
      post "#{root}/preview", headers: actor.create_new_auth_token,
                              params: { file: Rack::Test::UploadedFile.new(file.path, 'text/csv') }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('token' => nil, 'rows' => [], 'errors' => [include('line' => 2)])
      expect(response.body).not_to include(operator_b.name, operator_b.updated_at.iso8601(6))
      expect(operator_b.reload.name).to eq('Synthetic hidden API operator B')
    end
  end

  it 'rejects apply after losing corporate coverage instead of trusting a previously issued preview' do
    Tempfile.create(['synthetic-company-scope', '.csv']) do |file|
      file.write("id,name\n#{operator_a.id},Synthetic stale coverage request\n")
      file.flush
      post "#{root}/preview", headers: actor.create_new_auth_token,
                              params: { file: Rack::Test::UploadedFile.new(file.path, 'text/csv') }
      expect(response).to have_http_status(:ok)
      token = response.parsed_body.fetch('token')
      expect(token).to be_present
      grant.update!(active: false)
      post "#{root}/apply", headers: actor.create_new_auth_token,
                            params: { token: token, file: Rack::Test::UploadedFile.new(file.path, 'text/csv') }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(operator_a.reload.name).to eq('Synthetic API operator A')
    end
  end

  it 'rechecks the native administrator permission on a later apply request' do
    Tempfile.create(['synthetic-company-role', '.csv']) do |file|
      file.write("id,name\n#{operator_a.id},Synthetic stale role request\n")
      file.flush
      post "#{root}/preview", headers: actor.create_new_auth_token,
                              params: { file: Rack::Test::UploadedFile.new(file.path, 'text/csv') }
      token = response.parsed_body.fetch('token')
      expect(token).to be_present
      account.account_users.find_by!(user: actor).update!(role: :agent)
      post "#{root}/apply", headers: actor.create_new_auth_token,
                            params: { token: token, file: Rack::Test::UploadedFile.new(file.path, 'text/csv') }
      expect(response).to have_http_status(:unauthorized)
      expect(operator_a.reload.name).to eq('Synthetic API operator A')
    end
  end
end
