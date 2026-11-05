require 'rails_helper'

RSpec.describe 'Public Survey Responses API', type: :request do
  describe 'GET public/api/v1/csat_survey/{uuid}' do
    it 'return the csat response for that conversation' do
      conversation = create(:conversation)
      create(:message, conversation: conversation, content_type: 'input_csat')
      get "/public/api/v1/csat_survey/#{conversation.uuid}"
      data = response.parsed_body
      expect(response).to have_http_status(:success)
      expect(data['conversation_id']).to eq conversation.id
    end

    it 'returns not found error for the open conversation' do
      conversation = create(:conversation)
      create(:message, conversation: conversation, content_type: 'text')
      get "/public/api/v1/csat_survey/#{conversation.uuid}"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'PUT public/api/v1/csat_survey/{uuid}' do
    params = { message: { submitted_values: { csat_survey_response: { rating: 4, feedback_message: 'amazing experience' } } } }
    it 'updates only the UUID-scoped conversation for a contact with two surveys without reopening either conversation' do
      account = create(:account)
      inbox = create(:channel_api, account: account).inbox
      contact = create(:contact, account: account)
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
      conversations = create_list(
        :conversation, 2, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :resolved
      )
      messages = conversations.map { |value| MessageTemplates::Template::CsatSurvey.new(conversation: value).perform }

      patch "/public/api/v1/csat_survey/#{conversations.first.uuid}", params: params, as: :json

      expect(response).to have_http_status(:success)
      event = Events::Base.new('message.updated', Time.current, message: messages.first.reload)
      CsatSurveyListener.instance.message_updated(event)
      survey_response = messages.first.reload.csat_survey_response
      expect(survey_response).to have_attributes(
        account_id: account.id, contact_id: contact.id, conversation_id: conversations.first.id, message_id: messages.first.id, rating: 4
      )
      expect(messages.last.reload.csat_survey_response).to be_nil
      expect(messages.last.content_attributes['submitted_values']).to be_blank
      expect(conversations.map { |value| value.reload.status }).to eq(%w[resolved resolved])
      expect(conversations.map { |value| value.messages.incoming.count }).to eq([0, 0])
    end

    it 'update csat survey response for the conversation' do
      conversation = create(:conversation)
      message = create(:message, conversation: conversation, content_type: 'input_csat')
      # since csat survey is created in async job, we are mocking the creation.
      create(:csat_survey_response, conversation: conversation, message: message, rating: 4, feedback_message: 'amazing experience')
      patch "/public/api/v1/csat_survey/#{conversation.uuid}",
            params: params,
            as: :json
      expect(response).to have_http_status(:success)
      data = response.parsed_body
      expect(data['conversation_id']).to eq conversation.id
      expect(data['csat_survey_response']['conversation_id']).to eq conversation.id
      expect(data['csat_survey_response']['feedback_message']).to eq 'amazing experience'
      expect(data['csat_survey_response']['rating']).to eq 4
    end

    it 'returns update error if CSAT message sent more than 14 days' do
      conversation = create(:conversation)
      message = create(:message, conversation: conversation, content_type: 'input_csat', created_at: 15.days.ago)
      create(:csat_survey_response, conversation: conversation, message: message, rating: 4, feedback_message: 'amazing experience')
      patch "/public/api/v1/csat_survey/#{conversation.uuid}",
            params: params,
            as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
