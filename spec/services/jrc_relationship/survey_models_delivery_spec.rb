require 'rails_helper'

RSpec.describe 'V3 survey native delivery with a simulated provider' do
  include_context 'Service Desk survey models V3'
  include ActiveSupport::Testing::TimeHelpers

  let(:wa_channel) { create(:channel_whatsapp, account: sd_account) }
  let(:wa_inbox) { create(:inbox, account: sd_account, channel: wa_channel) }
  let(:email_inbox) { create(:inbox, :with_email, account: sd_account) }
  let(:wa_conversation) { create(:conversation, account: sd_account, contact: sd_contact, inbox: wa_inbox, assignee: sd_user) }
  let(:email_conversation) { create(:conversation, account: sd_account, contact: sd_contact, inbox: email_inbox, assignee: sd_user) }
  let(:ticket) { sd_ticket }
  let(:payload) do
    survey_payload.deep_dup.tap do |data|
      data['channels']['whatsapp'] = { 'enabled' => true, 'inbox_id' => wa_inbox.id, 'message' => 'Synthetic WhatsApp invite {{survey_link}}' }
      data['channels']['email'] = { 'enabled' => true, 'inbox_id' => email_inbox.id, 'message' => 'Synthetic email invite {{survey_link}}' }
    end
  end
  let(:model) { publish_survey_model(payload) }
  let(:survey) do
    model
    ticket.update!(status: create(:jrc_sd_status, unit: sd_unit, phase: 'closed', initial: false))
    JrcRelationship::SurveyEngine.evaluate_event(source: ticket, event: 'closure', cycle_key: "delivery:#{ticket.id}").survey
  end

  before do
    stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook').to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, 'https://waba.360dialog.io/v1/configs/templates').to_return(status: 200, body: { waba_templates: [] }.to_json, headers: { 'Content-Type' => 'application/json' })
    sd_contact.update!(email: 'recipient@disposable-mail.invalid')
    [wa_inbox, email_inbox].each { |inbox| create(:inbox_member, inbox: inbox, user: sd_user) }
    create(:message, account: sd_account, conversation: wa_conversation, sender: sd_contact, message_type: :incoming,
      content: 'Synthetic incoming message opening the permitted reply window')
    email_conversation
  end

  it 'selects one channel, queues a real native message, records a provider receipt and validates its response' do
    expect(survey.rule_snapshot.dig('settings', 'channel')).to eq('whatsapp')
    expect do
      JrcRelationship::SurveyDispatchJob.perform_now(survey.id)
    end.to change(Message, :count).by(1)
    message = Message.find(survey.reload.metadata.fetch('sent_message_id'))
    expect(message.conversation).to eq(wa_conversation)
    expect(message.conversation.contact).to eq(ticket.requester)
    expect(message.content).to start_with('Synthetic WhatsApp invite https://surveys.disposable-mail.invalid/jrc/relacionamento/pesquisas/')
    calls = 0
    2.times do
      JrcRelationship::SurveyMessageExecution.new(message).perform do
        calls += 1
        message.update!(source_id: 'synthetic-provider-receipt')
      end
    end
    expect(calls).to eq(1)
    expect(survey.reload.status).to eq('sent')
    message.update!(status: :delivered)
    JrcRelationship::SurveyReceiptJob.perform_now(message.id)
    expect(survey.reload).to have_attributes(status: 'delivered', provider_id: 'synthetic-provider-receipt')
    JrcRelationship::SurveyResponse.new(survey).call(answers: { score: 10 })
    expect(survey.reload.answers).to eq('score' => 10)
    expect(survey.classification).to eq('promoter')
  end

  it 'uses the next eligible configured channel before enrollment when WhatsApp has no authorized window' do
    wa_conversation.messages.update_all(created_at: 3.days.ago)
    expect(wa_conversation.can_reply?).to be(false)
    expect(survey.rule_snapshot.dig('settings', 'channel')).to eq('email')
    JrcRelationship::SurveyDispatchJob.perform_now(survey.id)
    message = Message.find(survey.reload.metadata.fetch('sent_message_id'))
    expect(message.conversation).to eq(email_conversation)
    expect(message.content).to start_with('Synthetic email invite ')
    expect(message.content_attributes['to_emails']).to eq(['recipient@disposable-mail.invalid'])
  end

  it 'never switches to another channel after an uncertain provider effect' do
    JrcRelationship::SurveyDispatchJob.perform_now(survey.id)
    message = Message.find(survey.reload.metadata.fetch('sent_message_id'))
    JrcRelationship::SurveyMessageExecution.new(message).perform { raise IOError, 'Synthetic uncertain provider result' }
    expect(survey.reload.status).to eq('unknown')
    repeated_calls = 0
    expect do
      JrcRelationship::SurveyDispatchJob.perform_now(survey.id)
      JrcRelationship::SurveyEventRecovery.new(sd_account).call
      JrcRelationship::SurveyMessageExecution.new(message).perform { repeated_calls += 1 }
    end.not_to change(Message, :count)
    expect(survey.reload.status).to eq('unknown')
    expect(repeated_calls).to eq(0)
    expect(survey.metadata['sent_message_id']).to eq(message.id)
    expect(email_conversation.messages.where("content_attributes->>'relationship_survey_id' = ?", survey.id.to_s)).to be_empty
  end

  it 'rechecks revoked consent at the provider boundary without provider I/O or another channel' do
    JrcRelationship::SurveyDispatchJob.perform_now(survey.id)
    message = Message.find(survey.reload.metadata.fetch('sent_message_id'))
    sd_contact.update!(custom_attributes: { 'survey_consent' => false })
    calls = 0
    JrcRelationship::SurveyMessageExecution.new(message).perform { calls += 1 }
    expect(calls).to eq(0)
    expect(survey.reload).to have_attributes(status: 'blocked', failure_code: 'contact_or_consent_revoked')
  end

  it 'honors configured delay and the weekly window without losing the selected channel' do
    data = payload.deep_dup
    data['rules']['delay_minutes'] = 30
    data['rules']['send_window'] = { 'enabled' => true, 'timezone' => 'America/Sao_Paulo', 'days' => [1, 2, 3, 4, 5], 'start' => '08:00', 'end' => '18:00' }
    travel_to Time.iso8601('2026-10-26T20:50:00Z')
    publish_survey_model(data)
    ticket.update!(status: create(:jrc_sd_status, unit: sd_unit, phase: 'closed', initial: false))
    row = JrcRelationship::SurveyEngine.evaluate_event(source: ticket, event: 'closure', cycle_key: 'window').survey
    expect(row.scheduled_at).to eq(Time.iso8601('2026-10-27T11:00:00Z'))
    expect { JrcRelationship::SurveyDispatchJob.perform_now(row.id) }.not_to change(Message, :count)
    expect(row.reload.status).to eq('scheduled')
  ensure
    travel_back
  end

  it 'uses explicit Account context for options and does not borrow a different Current Account' do
    Current.account = sd_foreign_account
    options = survey_editor.options(sd_unit.id)
    expect(options[:inboxes].pluck(:id)).to include(wa_inbox.id, email_inbox.id)
    expect(options[:units].pluck(:id)).to eq([sd_unit.id])
    expect { publish_survey_model(payload) }.not_to raise_error
  ensure
    Current.reset
  end

  it 'does not grant an executor the administrator configurator inboxes' do
    executor = create(:account_user, account: sd_account, role: :agent)
    create(:jrc_sd_membership, unit: sd_unit, account_user: executor)
    data = payload.deep_dup
    data['rules']['execution_member_id'] = executor.id
    row = survey_editor.save(payload: data)
    Current.account = sd_account
    Current.user = sd_user
    Current.account_user = sd_account_user
    expect do
      survey_editor.publish(id: row.id, expected_version: row.lock_version, request_key: SecureRandom.uuid)
    end.to raise_error(JrcRelationship::SurveyModelContract::Invalid)
    expect(row.reload.definition_id).to be_nil
  ensure
    Current.reset
  end
end
