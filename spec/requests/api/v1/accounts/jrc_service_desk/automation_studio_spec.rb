# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk automation studio', type: :request do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:root) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:queue) { create(:jrc_sd_queue, unit: sd_unit) }
  let(:source) { lc_publish(definition: lc_definition(tracked: true)).current_version }
  let(:target) { lc_publish(definition: JrcServiceDesk::ClosureRevisionBinding.proposal(source), expected_version: 1).current_version }
  let(:ticket) { sd_ticket(lifecycle_policy_version: source) }
  let(:publisher) { JrcServiceDesk::PublishNotificationPolicyService.new(user_context: sd_context) }
  let(:policy_attributes) do
    { event_type: 'closed', channel: 'email', enabled: false, confirmed: true, expected_version: 0,
      inbox_id: nil, template: 'Ticket {{number}}: {{title}}', template_version: 'test-v1',
      display_name: 'Closure notification', description: 'Synthetic description' }
  end

  before { sd_as_admin! }

  it 'stores presentation metadata in a new immutable notification version without sending anything' do
    expect do
      expect do
        policy = publisher.call(unit_id: sd_unit.id, attributes: policy_attributes)
        expect(policy.display_name).to eq('Closure notification')
        expect(policy.description).to eq('Synthetic description')
      end.not_to change(Message, :count)
    end.not_to change(JrcServiceDesk::NotificationDelivery, :count)
  end

  it 'preserves the metadata when a legacy editor omits it on the next version' do
    first = publisher.call(unit_id: sd_unit.id, attributes: policy_attributes)
    before = first.attributes.deep_dup
    next_attributes = policy_attributes.except(:display_name, :description).merge(expected_version: 1, template: 'Updated {{number}}')
    second = publisher.call(unit_id: sd_unit.id, attributes: next_attributes)
    expect(second.attributes.values_at('display_name', 'description')).to eq(['Closure notification', 'Synthetic description'])
    expect(first.reload.attributes).to eq(before)
    expect(second.version).to eq(2)
  end

  it 'rejects an obsolete notification version rather than overwriting the publication' do
    publisher.call(unit_id: sd_unit.id, attributes: policy_attributes)
    expect { publisher.call(unit_id: sd_unit.id, attributes: policy_attributes) }.to raise_error(JrcServiceDesk::IdempotencyConflict)
    expect(JrcServiceDesk::NotificationPolicyVersion.count).to eq(1)
  end

  it 'rejects non-text metadata and overlong descriptions without adding versions' do
    expect { publisher.call(unit_id: sd_unit.id, attributes: policy_attributes.merge(display_name: { bad: true })) }.to raise_error(ArgumentError)
    expect do
      publisher.call(unit_id: sd_unit.id, attributes: policy_attributes.merge(description: 'x' * 4001))
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(JrcServiceDesk::NotificationPolicyVersion.count).to eq(0)
  end

  it 'reports no clock and no delivery as unavailable coverage rather than successful SLA or delivery' do
    queue
    get "#{root}/automation_insights/ola", headers: headers, params: { unit_id: sd_unit.id, queue_id: queue.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.values_at('total', 'queues_total', 'items')).to eq([0, 1, []])
    get "#{root}/automation_insights/notifications", headers: headers, params: { unit_id: sd_unit.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.values_at('confirmed_sent', 'delivery_rate')).to eq([0, nil])
  end

  it 'does not create an audit, a clock or a notification when querying insight panels' do
    queue
    audits = Audited::Audit.count
    expect do
      expect do
        get "#{root}/automation_insights/ola", headers: headers, params: { unit_id: sd_unit.id }
        expect(response).to have_http_status(:ok)
        get "#{root}/automation_insights/notifications", headers: headers, params: { unit_id: sd_unit.id }
        expect(response).to have_http_status(:ok)
      end.not_to change(JrcServiceDesk::OlaClock, :count)
    end.not_to change(JrcServiceDesk::NotificationDelivery, :count)
    expect(Audited::Audit.count).to eq(audits)
  end

  it 'rejects a foreign unit and a cross-unit queue even for a local administrator' do
    foreign_queue = create(:jrc_sd_queue, unit: sd_other_unit)
    get "#{root}/automation_insights/ola", headers: headers, params: { unit_id: sd_unit.id, queue_id: foreign_queue.id }
    expect(response).to have_http_status(:not_found)
    get "#{root}/automation_insights/notifications", headers: headers, params: { unit_id: sd_foreign_unit.id }
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects an invalid observation period and denies an unprivileged actor' do
    get "#{root}/automation_insights/notifications", headers: headers, params: { unit_id: sd_unit.id, days: 91 }
    expect(response).to have_http_status(:unprocessable_entity)
    sd_account_user.update!(role: :agent)
    get "#{root}/automation_insights/notifications", headers: headers, params: { unit_id: sd_unit.id }
    expect(response).to have_http_status(:forbidden)
  end

  it 'records the signed selection before enqueue, then applies through the authorized native worker' do
    source
    target
    before = ticket.attributes.except('updated_at', 'lock_version')
    post "#{root}/closure_revisions/preview", headers: headers, as: :json, params: {
      unit_id: sd_unit.id, source_version_id: source.id, target_version_id: target.id,
      ticket_ids: [ticket.id], operational_review: true, review_reason: 'Explicit synthetic administrative review', review_name: 'Synthetic audited revision'
    }
    expect(response).to have_http_status(:ok)
    receipt = response.parsed_body.fetch('preview').fetch('receipt')
    key = 'async-studio-test'
    expect do
      post "#{root}/closure_revisions/enqueue", headers: headers.merge('Idempotency-Key' => key), as: :json,
                                                params: { unit_id: sd_unit.id, receipt: receipt }
    end.to have_enqueued_job(JrcServiceDesk::ClosureRevisionJob).with(sd_account.id, sd_account_user.id, sd_user.id, sd_unit.id, key)
    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body.dig('result', 'complete')).to be(false)
    expect(ticket.ticket_events.where(event_type: 'closure_policy_revised').count).to eq(0)
    2.times do
      JrcServiceDesk::ClosureRevisionJob.perform_now(sd_account.id, sd_account_user.id, sd_user.id, sd_unit.id, key)
    end
    expect(ticket.reload.attributes.except('updated_at', 'lock_version')).to eq(before)
    expect(ticket.ticket_events.where(event_type: 'closure_policy_revised').count).to eq(1)
    get "#{root}/closure_revisions/result", headers: headers, params: { unit_id: sd_unit.id, idempotency_key: key }
    expect(response.parsed_body.dig('result', 'complete')).to be(true)
    expect(response.parsed_body.dig('result', 'results').sole['status']).to eq('applied')
    expect(response.parsed_body.dig('result', 'review_name')).to eq('Synthetic audited revision')
  end

  it 'rechecks revoked authority in the worker and never applies with a stale grant' do
    source
    target
    service = JrcServiceDesk::ClosureRevisionService.new(user_context: sd_context)
    preview = service.preview(unit_id: sd_unit.id, source_version_id: source.id, target_version_id: target.id,
                              ticket_ids: [ticket.id], operational_review: true, review_reason: 'Synthetic scoped batch')
    service.enqueue(unit_id: sd_unit.id, receipt: preview[:receipt], idempotency_key: 'revoked-studio-test')
    sd_account_user.update!(role: :agent)
    expect do
      JrcServiceDesk::ClosureRevisionJob.perform_now(sd_account.id, sd_account_user.id, sd_user.id, sd_unit.id, 'revoked-studio-test')
    end.to raise_error(Pundit::NotAuthorizedError)
    expect(ticket.ticket_events.where(event_type: 'closure_policy_revised').count).to eq(0)
  end

  it 'does not accept an actor identifier from another Account in the worker' do
    foreign = create(:account_user, account: sd_foreign_account)
    expect do
      JrcServiceDesk::ClosureRevisionJob.perform_now(sd_account.id, foreign.id, foreign.user_id, sd_unit.id, 'foreign-studio-test')
    end.to raise_error(ActiveRecord::RecordNotFound)
  end
end
