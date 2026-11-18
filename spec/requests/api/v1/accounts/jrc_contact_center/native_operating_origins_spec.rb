require 'rails_helper'

RSpec.describe 'Call Center operating origin and native visibility', type: :request do
  self.use_transactional_tests = false

  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:headers) { actor.create_new_auth_token }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC origin issuer', relationship_type: 'internal') }
  let(:business_units) do
    %w[A B].map do |code|
      JrcCrm::BusinessUnit.create!(account: account, operating_company: company, code: code, name: "SYNTHETIC origin #{code}")
    end
  end
  let(:units) do
    business_units.map do |business_unit|
      JrcContactCenter::Unit.create!(account: account, code: business_unit.code, name: business_unit.name, kind: 'sac',
                                    settings: { issuer_company_id: company.id, business_unit_id: business_unit.id })
    end
  end
  let(:queue) { JrcContactCenter::Queue.create!(account: account, unit: units.first, code: 'SYNTHETIC', name: 'SYNTHETIC origin queue') }
  let(:calls) do
    [units.first, units.last, units.first].map.with_index do |unit, index|
      JrcContactCenter::CallSession.create!(account: account, current_unit: unit, current_queue: index == 1 ? nil : queue,
                                            provider: 'synthetic', correlation_id: SecureRandom.uuid, direction: 'inbound',
                                            status: 'connected', started_at: Time.current)
    end
  end
  let(:state) { {} }

  before do
    owned = Rails.env.test? && ActiveRecord::Base.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned synthetic database required' unless owned
    raise 'Committed fixtures required' if ActiveRecord::Base.connection.transaction_open?

    state[:ready] = true
    account.enable_features!('jrc_contact_center', 'custom_roles')
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_operate])
    member.update!(custom_role: role)
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'BUSINESS_UNIT', company: company,
                                   business_unit: business_units.first, active: true, structure_managed: true)
    JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member)
    calls.first(2).each do |call|
      JrcContactCenter::CallLeg.create!(account: account, call_session: call, account_user: member,
                                      direction: 'inbound', status: 'connected', started_at: Time.current)
    end
  end

  after do
    if state[:ready]
      models = [JrcContactCenter::Callback, JrcContactCenter::CaseEvent, JrcContactCenter::Case, JrcContactCenter::CallLeg,
                JrcContactCenter::CallSession, JrcContactCenter::QueueMembership, JrcContactCenter::Queue, JrcContactCenter::Unit,
                JrcCrm::UserBusinessUnit, JrcCrm::BusinessUnit]
      [account, state[:foreign_account]].compact.each do |owned_account|
        models.each { |model| model.where(account: owned_account).destroy_all }
        owned_account.master_companies.destroy_all
        owned_account.destroy!
      end
    end
  end

  %w[cases callbacks].each do |resource|
    context "with #{resource} from a call" do
      let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/#{resource}" }
      let(:key) { resource == 'cases' ? :case : :callback }
      let(:model) { resource == 'cases' ? JrcContactCenter::Case : JrcContactCenter::Callback }
      let(:payload) do
        shared = { call_session_id: calls.first.id, owner_account_user_id: member.id }
        if resource == 'cases'
          shared.merge(channel: 'phone', category: 'general', summary: 'SYNTHETIC visible origin')
        else
          shared.merge(target_phone: '+5511999999999', scheduled_at: 1.hour.from_now.iso8601, idempotency_key: SecureRandom.uuid)
        end
      end

      it 'derives the omitted queue from the authorized call and remains visible after creation' do
        post endpoint, headers: headers, params: { key => payload }, as: :json
        expect(response).to have_http_status(:created)
        record = model.where(account: account).sole
        expect(record).to have_attributes(queue_id: queue.id, call_session_id: calls.first.id)
        get endpoint, headers: headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.fetch('items').pluck('id')).to include(record.id)
      end

      it 'rejects a same-account call outside current corporate coverage, even with an operator leg' do
        post endpoint, headers: headers, params: { key => payload.merge(call_session_id: calls.second.id) }, as: :json
        expect(response).to have_http_status(:not_found)
        expect(model.where(account: account)).to be_empty
      end

      it 'rejects an unassigned call in the same permitted unit instead of treating the queue as call access' do
        post endpoint, headers: headers, params: { key => payload.merge(call_session_id: calls.third.id) }, as: :json
        expect(response).to have_http_status(:not_found)
        expect(model.where(account: account)).to be_empty
      end

      it 'rejects a foreign-account source before reaching a composite foreign-key error' do
        other = create(:account)
        state[:foreign_account] = other
        foreign = JrcContactCenter::CallSession.create!(account: other, provider: 'synthetic', correlation_id: SecureRandom.uuid,
                                                       direction: 'inbound', status: 'connected', started_at: Time.current)
        post endpoint, headers: headers, params: { key => payload.merge(call_session_id: foreign.id) }, as: :json
        expect(response).to have_http_status(:not_found)
        expect(model.where(account: account)).to be_empty
      end

      it 'preserves the record and its original call when a source update is unauthorized' do
        post endpoint, headers: headers, params: { key => payload }, as: :json
        record = model.where(account: account).sole
        previous = record.attributes
        patch "#{endpoint}/#{record.id}", headers: headers, params: { key => { call_session_id: calls.second.id } }, as: :json
        expect(response).to have_http_status(:not_found)
        expect(record.reload.attributes).to eq(previous)
      end

      it 'does not commit a new unbound record that native corporate scope would immediately hide' do
        attributes = payload.except(:call_session_id)
        post endpoint, headers: headers, params: { key => attributes }, as: :json
        expect(response).to have_http_status(:not_found)
        expect(model.where(account: account)).to be_empty
        expect(JrcContactCenter::CaseEvent.where(account: account)).to be_empty
      end

      it 'does not bypass native queue membership when inheriting the source queue' do
        JrcContactCenter::QueueMembership.where(account: account, account_user: member).destroy_all
        post endpoint, headers: headers, params: { key => payload }, as: :json
        expect(response).to have_http_status(:unauthorized)
        expect(model.where(account: account)).to be_empty
      end
    end
  end

  it 'persists the Case operational unit from the authorized call without a client-provided unit' do
    post "/api/v1/accounts/#{account.id}/jrc_contact_center/cases", headers: headers,
         params: { case: { call_session_id: calls.first.id, owner_account_user_id: member.id,
                           category: 'general', summary: 'SYNTHETIC unit', channel: 'phone' } }, as: :json
    expect(response).to have_http_status(:created)
    record = JrcContactCenter::Case.where(account: account).sole
    expect(record.unit_id).to eq(units.first.id)
    expect(record.events.pluck(:event_type)).to eq(['created'])
  end

  it 'rejects an explicit forbidden operational unit instead of replacing it silently with the source unit' do
    post "/api/v1/accounts/#{account.id}/jrc_contact_center/cases", headers: headers,
         params: { case: { call_session_id: calls.first.id, owner_account_user_id: member.id, unit_id: units.last.id,
                           category: 'general', summary: 'SYNTHETIC forbidden unit', channel: 'phone' } }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(JrcContactCenter::Case.where(account: account)).to be_empty
  end

  it 'rejects a callback linked to a hidden Case rather than relying only on its own visible queue' do
    hidden = JrcContactCenter::Case.create!(account: account, protocol: 'SYNTHETIC-HIDDEN', unit: units.last,
                                           channel: 'phone', category: 'general', summary: 'SYNTHETIC hidden')
    post "/api/v1/accounts/#{account.id}/jrc_contact_center/callbacks", headers: headers,
         params: { callback: { case_id: hidden.id, call_session_id: calls.first.id, owner_account_user_id: member.id,
                               target_phone: '+5511999999999', scheduled_at: 1.hour.from_now.iso8601,
                               idempotency_key: SecureRandom.uuid } }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(JrcContactCenter::Callback.where(account: account)).to be_empty
  end
end
