require 'rails_helper'

# Real authenticated JSON requests and native scopes; no source request may
# occur when a malformed filter could otherwise be discarded as blank.
RSpec.describe 'Control Desk strict optional recording filter shapes', :pabx, type: :request do
  include_context 'with native authorized quality review source'

  let(:headers) { actor.create_new_auth_token }
  let(:metric_reader) { instance_double(JrcVoiceQuality::AnalysisMetricReader, call: {}) }

  before do
    allow(JrcVoiceQuality::AnalysisMetricReader).to receive(:new).and_return(metric_reader)
  end

  %w[recordings recordings/quality_report].each do |endpoint|
    [
      { unit_id: false }, { unit_id: [] }, { queue_id: false }, { queue_id: {} },
      { from: false }, { from: [] }, { to: false }, { to: {} }
    ].each do |criteria|
      it "rejects supplied malformed #{criteria.inspect} on #{endpoint} without returning an unfiltered page" do
        get "/api/v1/accounts/#{account.id}/jrc_contact_center/#{endpoint}", headers: headers, params: criteria, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expected = criteria.keys.intersect?(%i[from to]) ? 'invalid_recording_range' : 'invalid_recording_filter'
        expect(response.parsed_body.fetch('error')).to eq(expected)
        expect(response.parsed_body).not_to have_key('items')
        expect(response.parsed_body).not_to have_key('quality_summary')
        expect(metric_reader).not_to have_received(:call)
      end
    end

    [{}, { unit_id: '', queue_id: '', from: '', to: '' }].each do |criteria|
      it "preserves the native empty-filter defaults #{criteria.inspect} on #{endpoint}" do
        get "/api/v1/accounts/#{account.id}/jrc_contact_center/#{endpoint}", headers: headers, params: criteria, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.fetch('meta')).to include('total' => 1)
        expect(response.parsed_body.fetch('items').sole.fetch('id')).to eq(record.id.to_s)
      end
    end
  end
end
