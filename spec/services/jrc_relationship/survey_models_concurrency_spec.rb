require 'rails_helper'

RSpec.describe 'Committed survey model concurrency and recovery', :sd_concurrency do
  self.use_transactional_tests = false
  include_context 'Service Desk survey models V3'
  include JrcServiceDeskConcurrency
  include JrcServiceDeskLifecycleFixtures

  it 'serializes two real PostgreSQL draft writes and preserves the successful edit' do
    row = survey_editor.save(payload: survey_payload.deep_dup)
    version = row.lock_version
    operations = %w[first second].map do |name|
      lambda do
        JrcRelationship::SurveyModelEditor.new(JrcRelationship::Context.new(sd_account_user)).save(
          id: row.id, expected_version: version, payload: survey_payload.merge('name' => name))
      end
    end
    results = concurrently(operations)
    expect(results.count { |value| value.is_a?(JrcRelationship::SurveyModelDraft) }).to eq(1)
    expect(results.count { |value| value.class.name == 'ActiveRecord::StaleObjectError' }).to eq(1)
    expect(%w[first second]).to include(row.reload.payload['name'])
    expect(row.lock_version).to eq(version + 1)
  end

  it 'publishes exactly one native definition/rule/version for simultaneous retries of the same key' do
    row = survey_editor.save(payload: survey_payload.deep_dup)
    version, key = row.lock_version, SecureRandom.uuid
    operations = 2.times.map do
      lambda do
        JrcRelationship::SurveyModelEditor.new(JrcRelationship::Context.new(sd_account_user)).publish(
          id: row.id, expected_version: version, request_key: key)
      end
    end
    results = concurrently(operations)
    expect(results).to all(be_a(JrcRelationship::SurveyModelDraft))
    expect(results.map(&:id).uniq).to eq([row.id])
    expect(JrcRelationship::SurveyDefinition.where(account: sd_account).count).to eq(1)
    expect(JrcRelationship::SurveyRule.where(account: sd_account).count).to eq(1)
    expect(JrcRelationship::SurveyVersion.where(account: sd_account, entity_type: 'JrcRelationship::SurveyDefinition').count).to eq(1)
    expect(JrcRelationship::Survey.where(account: sd_account)).to be_empty
  end

  it 'recovers a committed closure event after queue failure without reopening or duplicating the ticket' do
    publish_survey_model
    lc_publish
    ticket = sd_ticket
    allow(JrcRelationship::SurveyClosureJob).to receive(:perform_later).and_raise(IOError, 'Synthetic queue outage')
    lc_execute(ticket, 'resolve')
    lc_execute(ticket, 'close')
    expect(ActiveRecord::Base.connection.transaction_open?).to be(false)
    expect(ticket.reload.status.phase).to eq('closed')
    expect(JrcRelationship::Survey.where(account: sd_account)).to be_empty
    2.times { JrcRelationship::SurveyEventRecovery.new(sd_account).call }
    expect(JrcRelationship::Survey.where(account: sd_account).count).to eq(1)
    survey = JrcRelationship::Survey.where(account: sd_account).sole
    JrcRelationship::SurveyDispatchJob.perform_now(survey.id)
    expect(survey.reload.status).to eq('available')
    expect(ticket.reload.status.phase).to eq('closed')
    expect(ticket.lifecycle_transitions.pluck(:action)).to eq(%w[resolve close])
  end

  it 'recovers the committed decision when enqueue fails after the enrollment transaction committed' do
    publish_survey_model
    ticket = sd_ticket
    ticket.update!(status: create(:jrc_sd_status, unit: sd_unit, phase: 'closed', initial: false))
    allow_any_instance_of(JrcRelationship::SurveyDispatchJob).to receive(:enqueue).and_raise(IOError, 'Synthetic adapter outage')
    expect do
      JrcRelationship::SurveyEngine.evaluate_event(source: ticket, event: 'closure', cycle_key: 'commit-enqueue-gap')
    end.to raise_error(IOError)
    expect(ActiveRecord::Base.connection.transaction_open?).to be(false)
    expect(JrcRelationship::SurveyDispatchDecision.where(account: sd_account).count).to eq(1)
    expect(JrcRelationship::Survey.where(account: sd_account).count).to eq(1)
    allow_any_instance_of(JrcRelationship::SurveyDispatchJob).to receive(:enqueue).and_call_original
    JrcRelationship::SurveyEventRecovery.new(sd_account).call
    survey = JrcRelationship::Survey.where(account: sd_account).sole
    JrcRelationship::SurveyDispatchJob.perform_now(survey.id)
    expect(survey.reload.status).to eq('available')
  end
end
