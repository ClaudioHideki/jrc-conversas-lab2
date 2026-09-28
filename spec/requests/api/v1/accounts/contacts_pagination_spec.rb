require 'rails_helper'

RSpec.describe 'Contact pagination with equal sort values', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:headers) { agent.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/contacts" }

  it 'retains all tied contacts across regular and search pages' do
    contacts = create_list(:contact, 31, :with_email, account: account, name: 'Cliente', last_activity_at: 1.day.ago.change(usec: 0))
    expected = contacts.map(&:id).sort
    [url, "#{url}/search"].each do |endpoint|
      ids = (1..3).flat_map do |page|
        get endpoint, params: { page: page, sort: 'name', q: 'Cliente' }, headers: headers
        expect(response).to have_http_status(:ok)
        response.parsed_body.fetch('payload').map { |item| item['id'] }
      end
      expect(ids).to eq(expected)
      expect(ids.uniq.size).to eq(31)
    end
  end
end
