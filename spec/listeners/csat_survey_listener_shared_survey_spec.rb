require 'rails_helper'

RSpec.describe CsatSurveyListener do
  describe CsatSurveyListener do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account, csat_survey_enabled: true) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :resolved) }
    let(:event) { Events::Base.new('conversation.status_changed', Time.current, conversation: conversation) }

    it 'preserves native CSAT and records an ineligible closure when shared automation is off' do
      expect(JrcRelationship::SurveyEngine.enabled?(account)).to be(false)
      legacy = instance_double(CsatSurveyService, perform: nil)
      expect(CsatSurveyService).to receive(:new).with(conversation: conversation).and_return(legacy)

      expect { described_class.instance.conversation_status_changed(event) }
        .to have_enqueued_job(JrcRelationship::SurveyClosureJob)
        .with('Conversation', conversation.id, "conversation:#{conversation.id}:#{conversation.updated_at.utc.iso8601(6)}")

      cycle = "conversation:#{conversation.id}:#{conversation.updated_at.utc.iso8601(6)}"
      expect do
        2.times { JrcRelationship::SurveyClosureJob.perform_now('Conversation', conversation.id, cycle) }
      end.to change(JrcRelationship::SurveyDispatchDecision, :count).by(1)
      decision = JrcRelationship::SurveyDispatchDecision.last
      expect(decision.attributes.slice('account_id', 'state', 'reason', 'survey_id'))
        .to eq('account_id' => account.id, 'state' => 'skipped', 'reason' => 'automation_disabled', 'survey_id' => nil)
    end

    it 'uses exactly one survey engine instead of also invoking the legacy sender when enabled' do
      account.enable_features!('jrc_relationship')
      JrcRelationship::Configuration.create!(account: account, scope_key: 'account', rules: { 'survey_automation_enabled' => true })
      expect(CsatSurveyService).not_to receive(:new)

      expect { described_class.instance.conversation_status_changed(event) }
        .to have_enqueued_job(JrcRelationship::SurveyClosureJob).with('Conversation', conversation.id, anything)
    end

    it 'does not evaluate or send a survey when a conversation is still open' do
      conversation.update!(status: :open)
      expect(CsatSurveyService).not_to receive(:new)
      expect { described_class.instance.conversation_status_changed(event) }
        .not_to have_enqueued_job(JrcRelationship::SurveyClosureJob)
    end
  end

  describe JrcRelationship::NativeCsatResponseJob do
    it 'bridges an actual native CSAT response without replacing ResponseBuilder' do
      account = create(:account)
      account.enable_features!('jrc_relationship')
      conversation = create(:conversation, account: account)
      message = create(:message, account: account, inbox: conversation.inbox, conversation: conversation,
                                 content_type: :input_csat, message_type: :outgoing,
                                 content_attributes: {
                                   'submitted_values' => { 'csat_survey_response' => { 'rating' => 5, 'feedback_message' => 'Synthetic response' } }
                                 })

      expect { CsatSurveys::ResponseBuilder.new(message: message).perform }
        .to have_enqueued_job(described_class)
      response = message.reload.csat_survey_response
      expect(response.rating).to eq(5)
      expect(JrcRelationship::SurveyEngine).to receive(:native_csat_response).with(response)
      described_class.perform_now(response.id)
    end
  end
end
