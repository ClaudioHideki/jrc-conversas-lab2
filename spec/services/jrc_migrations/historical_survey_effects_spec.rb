# frozen_string_literal: true

require 'rails_helper'

# The real publication and import paths must not turn historical evidence into
# operational survey triggers, even after that evidence is accepted for NICO.
RSpec.describe JrcRelationship::SurveyEventSource do # rubocop:disable RSpec/SpecFilePathFormat
  include_context 'Service Desk survey models V3'
  include ActiveSupport::Testing::TimeHelpers

  before { sd_account.enable_features!('data_import') }
  after { clear_enqueued_jobs }

  def published_event_fixture(trigger)
    origin = 3.minutes.ago.change(usec: 0)
    ticket = nil
    travel_to(origin) do
      ticket = sd_ticket
      ticket.update!(status: create(:jrc_sd_status, unit: sd_unit, phase: 'closed', initial: false)) if trigger == 'closed'
    end
    payload = survey_payload.deep_dup
    payload['rules']['event'] = trigger
    travel_to(origin + 1.minute) { publish_survey_model(payload) }
    occurred_at = origin + 2.minutes
    expect_active_rule_before(occurred_at)
    [ticket, occurred_at]
  end

  def expect_active_rule_before(occurred_at)
    rule = JrcRelationship::SurveyRule.find_by!(account: sd_account)
    expect(rule.updated_at).to be < occurred_at
    expect(JrcRelationship::SurveyEngine.enabled?(sd_account)).to be(true)
  end

  def event_attributes(ticket, trigger, occurred_at)
    {
      'unit_id' => sd_unit.id, 'ticket_id' => ticket.id, 'actor_membership_id' => sd_membership.id,
      'event_type' => trigger == 'closed' ? 'lifecycle_transitioned' : 'first_response_observed',
      'visibility' => 'internal', 'data' => trigger == 'closed' ? { 'action' => 'close' } : {},
      'created_at' => occurred_at.iso8601(6), 'updated_at' => occurred_at.iso8601(6)
    }
  end

  def execute_history_batch(row)
    batch = JrcMigrations::Stage.new(account: sd_account, user: sd_user).call(
      source: 'synthetic-survey-history', domain: 'service_desk_events', rows: [row], mapping: {}
    )
    JrcMigrations::Preview.new(batch: batch, user: sd_user).call
    expect(batch.items.first.decision).to eq('create')
    JrcMigrations::Execute.new(batch: batch, user: sd_user).call
    batch
  end

  def expect_event_acceptance(batch, event, accepted)
    mapping = JrcMigrations::Mapping.find_by!(account: sd_account, domain: 'service_desk_events', target_id: event.id)
    if accepted
      JrcMigrations::Reconciliation.new(batch: batch, user: sd_user).accept!(note: 'Reviewed synthetic historical evidence')
      expect(mapping.reload.accepted_at).to be_present
    else
      expect(mapping.accepted_at).to be_nil
    end
  end

  def import_historical_event(trigger, accepted:)
    ticket, occurred_at = published_event_fixture(trigger)
    batch = execute_history_batch(event_attributes(ticket, trigger, occurred_at).merge('legacy_id' => "historic-#{trigger}"))
    item = batch.items.reload.sole
    expect(item.status).to eq('applied')
    event = JrcServiceDesk::TicketEvent.find(item.target_id)
    expect(event.created_at).to eq(occurred_at)
    expect_event_acceptance(batch, event, accepted)
    expect_no_survey_effects
    clear_enqueued_jobs
    event
  end

  def expect_no_survey_effects
    expect(JrcRelationship::Survey.where(account: sd_account)).to be_empty
    expect(JrcRelationship::SurveyDispatchDecision.where(account: sd_account)).to be_empty
  end

  acceptance_states = [false, true].freeze
  %w[first_agent_response closed].each do |trigger|
    acceptance_states.each do |accepted|
      it "does not recover imported #{trigger} evidence with acceptance #{accepted}" do
        event = import_historical_event(trigger, accepted: accepted)
        JrcRelationship::SurveyResponseEventJob.perform_now(event.id) if trigger == 'first_agent_response'
        2.times { JrcRelationship::SurveyEventRecovery.new(sd_account).call }

        aggregate_failures do
          expect(JrcRelationship::Survey.where(account: sd_account)).to be_empty
          expect(JrcRelationship::SurveyDispatchDecision.where(account: sd_account)).to be_empty
          expect(enqueued_jobs).to be_empty
          expect(event.reload).to be_persisted
        end
      end
    end

    it "continues recovering a native #{trigger} event once without a migration mapping" do
      ticket, occurred_at = published_event_fixture(trigger)
      event = JrcServiceDesk::TicketEvent.create!(
        event_attributes(ticket, trigger, occurred_at).except('updated_at').merge('account_id' => sd_account.id)
      )
      expect(JrcMigrations::Mapping.where(account: sd_account, domain: 'service_desk_events', target_id: event.id)).to be_empty
      # Reproduce a lost enqueue; recovery must still admit the native source.
      clear_enqueued_jobs
      2.times { JrcRelationship::SurveyEventRecovery.new(sd_account).call }

      aggregate_failures do
        expect(JrcRelationship::Survey.where(account: sd_account).count).to eq(1)
        expect(JrcRelationship::SurveyDispatchDecision.where(account: sd_account).sole.state).to eq('scheduled')
        expect(enqueued_jobs.map { |job| job[:job] }).to include(JrcRelationship::SurveyDispatchJob)
      end
    end
  end
end
