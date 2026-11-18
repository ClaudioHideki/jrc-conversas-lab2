require 'rails_helper'

RSpec.describe 'Call Center native operating write authority', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let!(:headers) { actor.create_new_auth_token }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:role) { create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_operate]) }
  let(:unit) { JrcContactCenter::Unit.create!(account: account, code: 'SYNTHETIC', name: 'SYNTHETIC write unit', kind: 'sac') }
  let(:queue) { JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'SYNTHETIC', name: 'SYNTHETIC write queue') }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles')
    member.update!(custom_role: role)
    JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member)
  end

  it 'preserves the case actor, event order and history when access is later withdrawn' do
    endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/cases"
    payload = { queue_id: queue.id, unit_id: unit.id, owner_account_user_id: member.id,
                category: 'general', summary: 'SYNTHETIC native history', channel: 'phone' }
    post endpoint, headers: headers, params: { case: payload }, as: :json
    record = JrcContactCenter::Case.where(account: account).sole
    patch "#{endpoint}/#{record.id}", headers: headers, params: { case: { status: 'waiting' } }, as: :json
    expect(record.events.order(:id).pluck(:event_type)).to eq(%w[created updated])
    expect(record.events.pluck(:actor_account_user_id).uniq).to eq([member.id])
    JrcContactCenter::AccessGrant.find_by!(account_user: member).update!(eligible: false)
    patch "#{endpoint}/#{record.id}", headers: headers, params: { case: { status: 'closed' } }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(record.reload.status).to eq('waiting')
    expect(record.events.count).to eq(2)
  end

  %w[cases callbacks].each do |resource|
    context "with native #{resource}" do
      let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/#{resource}" }
      let(:key) { resource == 'cases' ? :case : :callback }
      let(:model) { resource == 'cases' ? JrcContactCenter::Case : JrcContactCenter::Callback }
      let(:payload) do
        shared = { queue_id: queue.id, owner_account_user_id: member.id }
        if resource == 'cases'
          shared.merge(unit_id: unit.id, category: 'general', summary: 'SYNTHETIC operating write', channel: 'phone')
        else
          shared.merge(target_phone: '+5511999999999', scheduled_at: 1.hour.from_now.iso8601, idempotency_key: SecureRandom.uuid)
        end
      end
      let(:changes) { resource == 'cases' ? { status: 'waiting' } : { state: 'canceled' } }

      it 'keeps native creation and its own persisted origin and assignment' do
        post endpoint, headers: headers, params: { key => payload }, as: :json
        expect(response).to have_http_status(:created)
        record = model.where(account: account).sole
        expect(record).to have_attributes(queue_id: queue.id, owner_account_user_id: member.id)
        expect(response.parsed_body.fetch('item').fetch('id')).to eq(record.id)
      end

      it 'keeps native update and event history rather than replacing the record' do
        post endpoint, headers: headers, params: { key => payload }, as: :json
        record = model.where(account: account).sole
        patch "#{endpoint}/#{record.id}", headers: headers, params: { key => changes }, as: :json
        expect(response).to have_http_status(:ok)
        expect(record.reload.attributes).to include(changes.stringify_keys)
        expect(model.where(account: account).count).to eq(1)
      end

      it 'denies an update after eligibility is withdrawn and preserves existing history' do
        post endpoint, headers: headers, params: { key => payload }, as: :json
        record = model.where(account: account).sole
        previous = record.attributes
        JrcContactCenter::AccessGrant.find_by!(account_user: member).update!(eligible: false)
        patch "#{endpoint}/#{record.id}", headers: headers, params: { key => changes }, as: :json
        expect(response).to have_http_status(:unauthorized)
        expect(record.reload.attributes).to eq(previous)
      end

      it 'denies foreign-account credentials without creating a record' do
        other = create(:account)
        outsider = create(:user, :contact_center_eligible, account: other, role: :administrator)
        post endpoint, headers: outsider.create_new_auth_token, params: { key => payload }, as: :json
        expect(response).to have_http_status(:unauthorized)
        expect(model.where(account: account)).to be_empty
      end
    end
  end
end
