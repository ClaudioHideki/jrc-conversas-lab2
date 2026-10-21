# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcRelationship::SurveyEngine do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: admin) }
  let(:contact) { create(:contact, account: account, custom_attributes: { 'survey_consent' => true }) }
  let(:session) do
    JrcContactCenter::CallSession.create!(account: account, contact: contact, correlation_id: 'survey-call', direction: 'inbound',
                                          started_at: 2.minutes.ago, answered_at: 1.minute.ago, ended_at: Time.current, status: 'ended')
  end
  let(:definition) do
    JrcRelationship::SurveyDefinition.create!(account: account, name: 'Call NPS', code: 'call_nps', kind: 'nps', status: 'active',
                                              questions: [{ 'key' => 'rating', 'text' => 'Recommendation?', 'type' => 'scale',
                                                            'min' => 0, 'max' => 10, 'required' => true }])
  end

  it 'uses the existing engine and deduplication without sending a message' do
    account.enable_features!('jrc_contact_center', 'jrc_relationship', 'jrc_customer_master')
    JrcRelationship::Configuration.create!(account: account, rules: { survey_automation_enabled: true })
    JrcRelationship::SurveyRule.create!(account: account, name: 'Explicit call rule', definition: definition, execution_member: member,
                                        active: true, matchers: { 'source_type' => session.class.name }, settings: { 'channel' => 'public_link' })

    expect do
      first = described_class.evaluate_closure(source: session, cycle_key: 'call-cycle')
      second = described_class.evaluate_closure(source: session, cycle_key: 'call-cycle')
      expect(first.id).to eq(second.id)
      expect(first.state).to eq('scheduled')
      expect(first.survey).to have_attributes(source_type: session.class.name, source_id: session.id)
    end.not_to change(Message, :count)
    expect(JrcRelationship::Survey.where(account: account).count).to eq(1)
  end

  it 'does not apply a generic pre-existing survey rule to PABX calls' do
    account.enable_features!('jrc_contact_center', 'jrc_relationship', 'jrc_customer_master')
    JrcRelationship::Configuration.create!(account: account, rules: { survey_automation_enabled: true })
    JrcRelationship::SurveyRule.create!(account: account, name: 'Generic rule', definition: definition, execution_member: member,
                                        active: true, matchers: {}, settings: { 'channel' => 'public_link' })

    decision = described_class.evaluate_closure(source: session, cycle_key: 'generic-cycle')

    expect(decision.reason).to eq('execution_member_missing')
    expect(JrcRelationship::Survey.where(account: account)).to be_empty
  end

  it 'requires contact center permission and never maps a contact center unit to a service desk unit' do
    account.enable_features!('jrc_contact_center', 'jrc_relationship', 'jrc_customer_master')
    context = JrcRelationship::Context.new(member)
    source = JrcRelationship::SurveySource.new(session, context)
    expect(source.attributes).to include('unit_id' => nil, 'channel_type' => 'pabx_inbound')
    account.disable_features!('jrc_contact_center')

    expect { JrcRelationship::SurveySource.new(session, JrcRelationship::Context.new(member)) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'enqueues closure once even when reconciliation updates projection metadata in the same transaction' do
    account.enable_features!('jrc_contact_center', 'jrc_relationship', 'jrc_customer_master')
    JrcRelationship::Configuration.create!(account: account, rules: { survey_automation_enabled: true })
    JrcRelationship::SurveyRule.create!(account: account, name: 'Explicit call rule', definition: definition, execution_member: member,
                                        active: true, matchers: { 'source_type' => session.class.name }, settings: { 'channel' => 'public_link' })
    session.update!(status: 'connected', ended_at: nil)

    expect do
      session.class.transaction do
        session.update!(status: 'ended', ended_at: Time.current)
        session.update_f1_data('projection' => {})
      end
    end.to have_enqueued_job(JrcRelationship::SurveyClosureJob).with(session.class.name, session.id, "contact-center:#{session.id}")
  end
end
