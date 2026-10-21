require 'rails_helper'

RSpec.describe 'API Base', type: :request do
  self.use_transactional_tests = false

  describe 'request to api base url' do
    it 'returns api version' do
      get '/api/'
      expect(response).to have_http_status(:success)
      expect(response.body).to include(Chatwoot.config[:version])
      expect(response.body).to include('queue_services')
      expect(response.body).to include('data_services')
    end

    it 'checks PostgreSQL after a cold connection starts' do
      ActiveRecord::Base.connection.disconnect!

      expect(ApiController.new.send(:postgres_status)).to eq('ok')
    end
  end
end
