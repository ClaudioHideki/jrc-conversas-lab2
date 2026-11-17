require 'rails_helper'

RSpec.describe 'Call Center native configuration revisions', type: :request do
  let(:account) { create(:account) }
  let(:operator) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let!(:headers) { operator.create_new_auth_token }
  let(:member) { account.account_users.find_by!(user: operator) }
  let(:unit) { JrcContactCenter::Unit.create!(account: account, code: 'REVISION', name: 'Original', kind: 'sac') }
  let(:queue) { JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'REVISION', name: 'Original') }
  let(:membership) do
    JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member, role: 'agent')
  end
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center" }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_configure])
    member.update!(custom_role: role)
  end

  shared_examples 'a revision-protected native configuration' do |resource, parameter|
    let(:target) { public_send({ units: :unit, queues: :queue, queue_memberships: :membership }.fetch(resource)) }
    let(:url) { "#{base}/#{resource}/#{target.id}" }
    let(:change) { resource == :queue_memberships ? { priority: 2 } : { name: 'New draft' } }
    let(:current_token) { JrcContactCenter::ConfigurationRevision.token(target.reload) }

    it 'provides the authorized current revision and accepts the matching precondition' do
      get url, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to eq('no-store')
      captured = response.parsed_body.fetch('item').fetch('revision')
      expect(captured).to eq(current_token)
      patch url, headers: headers, params: { parameter => change }.merge(expected_revision: captured), as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('item').fetch('revision')).not_to eq(captured)
      expect(target.reload).to have_attributes(change)
    end

    it 'preserves the legacy update contract when the root precondition is omitted' do
      patch url, headers: headers, params: { parameter => change }, as: :json
      expect(response).to have_http_status(:ok)
      expect(target.reload).to have_attributes(change)
    end

    it 'rejects blank and non-string preconditions without mutation or a success audit' do
      target
      count = Audited.audit_class.where(auditable: target).count
      [nil, '', {}, ['invalid']].each do |invalid|
        patch url, headers: headers, params: { parameter => change }.merge(expected_revision: invalid), as: :json
        expect(response).to have_http_status(:precondition_required)
        expect(response.parsed_body.fetch('error')).to eq('configuration_revision_required')
      end
      expect(target.reload.attributes.slice(*change.keys.map(&:to_s))).not_to eq(change.stringify_keys)
      expect(Audited.audit_class.where(auditable: target).count).to eq(count)
    end

    it 'rejects a stale edit without discarding the concurrent state or writing a false success' do
      captured = current_token
      concurrent = resource == :queue_memberships ? { priority: 5 } : { name: 'Concurrent state' }
      target.update!(concurrent)
      count = Audited.audit_class.where(auditable: target).count
      patch url, headers: headers, params: { parameter => change }.merge(expected_revision: captured), as: :json
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body.fetch('error')).to eq('stale_configuration_revision')
      expect(target.reload).to have_attributes(concurrent)
      expect(Audited.audit_class.where(auditable: target).count).to eq(count)
    end

    it 'allows explicit reloading and a new edit with the refreshed authorized state' do
      previous = current_token
      target.update!(resource == :queue_memberships ? { priority: 7 } : { name: 'Refreshed state' })
      get url, headers: headers
      current = response.parsed_body.fetch('item').fetch('revision')
      expect(current).not_to eq(previous)
      patch url, headers: headers, params: { parameter => change }.merge(expected_revision: current), as: :json
      expect(response).to have_http_status(:ok)
      expect(target.reload).to have_attributes(change)
    end

    it 'denies a different business unit before comparing a valid or malformed revision' do
      target
      company = account.master_companies.create!(name: 'SYNTHETIC issuer', relationship_type: 'internal')
      business_units = %w[A B].map do |code|
        JrcCrm::BusinessUnit.create!(account: account, operating_company: company, code: code, name: "SYNTHETIC #{code}")
      end
      unit.update!(settings: { issuer_company_id: company.id, business_unit_id: business_units.last.id })
      authorized = JrcContactCenter::Unit.create!(
        account: account, code: 'AUTHORIZED', name: 'SYNTHETIC authorized', kind: 'sac',
        settings: { issuer_company_id: company.id, business_unit_id: business_units.first.id }
      )
      JrcCrm::UserBusinessUnit.create!(
        account: account, user: operator, scope: 'BUSINESS_UNIT', business_unit: business_units.first,
        company: company, active: true, structure_managed: true
      )
      get "#{base}/units/#{authorized.id}", headers: headers
      expect(response).to have_http_status(:ok)
      get url, headers: headers
      expect(response).to have_http_status(:not_found)
      [current_token, nil].each do |version|
        patch url, headers: headers, params: { parameter => change }.merge(expected_revision: version), as: :json
        expect(response).to have_http_status(:not_found)
        expect(response.body).not_to include('configuration_revision_required', 'stale_configuration_revision')
      end
      expect(target.reload.attributes.slice(*change.keys.map(&:to_s))).not_to eq(change.stringify_keys)
    end

    it 'denies a different account before evaluating the expected revision' do
      foreign = create(:account)
      target
      get url.sub("/accounts/#{account.id}/", "/accounts/#{foreign.id}/"), headers: headers
      expect(response).to have_http_status(:unauthorized)
      patch url.sub("/accounts/#{account.id}/", "/accounts/#{foreign.id}/"),
            headers: headers, params: { parameter => change }.merge(expected_revision: nil), as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(response.body).not_to include('stale_configuration_revision', 'configuration_revision_required')
    end
  end

  context 'with a local operational unit' do
    it_behaves_like 'a revision-protected native configuration', :units, :unit
  end

  context 'with a local queue' do
    it_behaves_like 'a revision-protected native configuration', :queues, :queue
  end

  context 'with a local queue membership' do
    it_behaves_like 'a revision-protected native configuration', :queue_memberships, :queue_membership
  end
end
