# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Explicit scoped preparation of v2 ending destinations', type: :request do
  include_context 'with native typed ending schema evidence'

  let(:headers) { actor.create_new_auth_token }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/acw_policy/ending_rules" }
  let(:request_key) { SecureRandom.uuid }

  def review
    { rule_code: 'SYNTHETIC_ORIGIN_RULE', request_key: request_key,
      expected_revision: JrcContactCenter::AcwPolicy.new(account: account.reload).revision }
  end

  def prepare_rule(document = review, authentication = headers)
    post "#{endpoint}/activate", headers: authentication, params: document, as: :json
  end

  def own_unit_coverage
    JrcCrm::UserBusinessUnit.where(account: account, user: actor, scope: 'GROUP').find_each { |row| row.update!(active: false) }
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'BUSINESS_UNIT', company: issuer,
                                   business_unit: business, active: true, structure_managed: true)
  end

  def native_effect_counts
    [JrcContactCenter::EndingDestinationAttempt.where(account: account).count,
     JrcContactCenter::EndingDestinationConsent.where(account: account).count,
     JrcProjects::Task.where(account: account).count]
  end

  it 'prepares the exact manual v2 definition without mistaking the rule review for an individual action consent' do
    count = JrcContactCenter::EndingActionReadiness.where(account: account).count
    prepare_rule
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item')).to include('prospective_only' => true, 'rule_code' => 'SYNTHETIC_ORIGIN_RULE')
    expect(JrcContactCenter::EndingActionReadiness.where(account: account).count).to eq(count + 1)
    expect(native_effect_counts).to eq([0, 0, 0])
    expect(JrcContactCenter::Qualification.where(account: account)).to be_empty
  end

  it 'permits only the current authorized unit preparation while the global ACW settings remain unavailable' do
    own_unit_coverage
    prepare_rule
    expect(response).to have_http_status(:ok)
    get "#{endpoint}/readiness", headers: headers, params: review.slice(:rule_code, :expected_revision)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('applicable_review')).to include('rule_code' => 'SYNTHETIC_ORIGIN_RULE')
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/acw_policy", headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(native_effect_counts).to eq([0, 0, 0])
  end

  it 'rechecks corporate coverage after a readable preparation state rather than trusting the earlier read' do
    own_unit_coverage
    get "#{endpoint}/readiness", headers: headers, params: review.slice(:rule_code, :expected_revision)
    expect(response).to have_http_status(:ok)
    before = JrcContactCenter::EndingActionReadiness.where(account: account).count
    JrcCrm::UserBusinessUnit.where(account: account, user: actor, active: true).find_each { |row| row.update!(active: false) }
    prepare_rule
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::EndingActionReadiness.where(account: account).count).to eq(before)
    expect(response.body).not_to include('SYNTHETIC unarmed original evidence')
  end

  it 'rejects a reviewed revision that was replaced without preparing the replacement rule silently' do
    document = review
    before = JrcContactCenter::EndingActionReadiness.where(account: account).count
    publish_typed_schema_definition('name' => 'SYNTHETIC changed after review')
    prepare_rule(document)
    expect(response).to have_http_status(:conflict)
    expect(JrcContactCenter::EndingActionReadiness.where(account: account).count).to eq(before)
    expect(native_effect_counts).to eq([0, 0, 0])
  end

  it 'does not reveal a foreign-unit inactive rule through a distinguishable readiness-state error' do
    publish_typed_schema_definition('active' => false)
    other = JrcCrm::BusinessUnit.create!(account: account, operating_company: issuer,
                                       code: 'SYNTHETIC_READY_OTHER', name: 'SYNTHETIC other covered unit')
    JrcContactCenter::Unit.create!(account: account, code: 'SYNTHETIC_READY_OTHER', name: 'SYNTHETIC other allowed source', kind: 'sac',
                                  settings: { 'issuer_company_id' => issuer.id.to_s, 'business_unit_id' => other.id.to_s })
    JrcCrm::UserBusinessUnit.where(account: account, user: actor, scope: 'GROUP').find_each { |row| row.update!(active: false) }
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'BUSINESS_UNIT', company: issuer,
                                   business_unit: other, active: true, structure_managed: true)
    count = JrcContactCenter::EndingActionReadiness.where(account: account).count
    prepare_rule
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('ending_action_not_ready', 'SYNTHETIC_ORIGIN_RULE', 'SYNTHETIC unarmed original evidence')
    expect(JrcContactCenter::EndingActionReadiness.where(account: account).count).to eq(count)
    expect(native_effect_counts).to eq([0, 0, 0])
  end

  context 'with an explicitly configured native CRM destination' do
    let(:typed_version) { publish_typed_schema_definition('actions' => [{ 'kind' => 'crm', 'parameters' => {} }]) }

    before do
      account.enable_features!('jrc_crm')
      member.update!(crm_enabled: true)
    end

    it 'prepares an authorized native CRM definition without creating customers, Leads or Activities' do
      contacts = account.contacts.count
      prepare_rule
      expect(response).to have_http_status(:ok)
      expect(account.contacts.count).to eq(contacts)
      expect(account.jrc_crm_leads).to be_empty
      expect(account.jrc_crm_activities).to be_empty
      expect(native_effect_counts).to eq([0, 0, 0])
    end

    it 'does not use stored readiness to bypass native CRM permission withdrawn before another preparation' do
      prepare_rule
      expect(response).to have_http_status(:ok)
      count = JrcContactCenter::EndingActionReadiness.where(account: account).count
      account.disable_features!('jrc_crm')
      prepare_rule(review.merge(request_key: SecureRandom.uuid))
      expect(response).to have_http_status(:unauthorized)
      expect(JrcContactCenter::EndingActionReadiness.where(account: account).count).to eq(count)
      expect(account.jrc_crm_leads).to be_empty
      expect(account.jrc_crm_activities).to be_empty
    end
  end

  it 'does not prepare another account rule using a valid foreign administrator credential' do
    foreign = create(:account)
    outsider = create(:user, :contact_center_eligible, account: foreign, role: :administrator)
    count = JrcContactCenter::EndingActionReadiness.where(account: account).count
    prepare_rule(review, outsider.create_new_auth_token)
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::EndingActionReadiness.where(account: account).count).to eq(count)
    expect(native_effect_counts).to eq([0, 0, 0])
  end

  context 'with a destination whose native configuration authority remains unavailable' do
    let(:typed_version) do
      publish_typed_schema_definition('actions' => [{ 'kind' => 'service_desk', 'parameters' => {
        'unit_id' => '1', 'service_id' => nil, 'attributes' => { 'title' => 'SYNTHETIC unavailable destination' }
      } }])
    end

    it 'refuses technical preparation instead of marking an unsupported Service Desk configuration operational' do
      count = JrcContactCenter::EndingActionReadiness.where(account: account).count
      prepare_rule
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JrcContactCenter::EndingActionReadiness.where(account: account).count).to eq(count)
      expect(native_effect_counts).to eq([0, 0, 0])
    end
  end
end
