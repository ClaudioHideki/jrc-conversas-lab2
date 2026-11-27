# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Explicit initial customer linkage from a native recording', :pabx do
  include_context 'with native authorized quality review source'

  let(:contact) { create(:contact, account: account, company: company, name: 'SYNTHETIC selected existing person') }
  let(:path) { "/api/v1/accounts/#{account.id}/jrc_contact_center/recordings/#{record.id}/customer_link" }
  let(:input) do
    { 'contact_id' => contact.id.to_s, 'call_session_id' => source_call.id.to_s,
      'call_id' => record.external_unique_id, 'lock_version' => source_call.reload.lock_version, 'confirm' => true }
  end

  before do
    account.enable_features!('jrc_customer_master')
    role.update!(permissions: role.permissions + %w[jrc_contact_center_operate contact_manage])
  end

  def write_link(values = input)
    post path, headers: actor.create_new_auth_token, params: { customer_link: values }, as: :json
  end

  def link_audits
    Audited.audit_class.where(associated: account, comment: JrcContactCenter::RecordingCustomerLink::COMMENT)
  end

  it 'previews only current identity and version without selecting a telephone candidate or reading Nico' do
    contact.update!(phone_number: record.caller)
    get path, headers: actor.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('account_id' => account.id.to_s, 'user_id' => actor.id.to_s,
                                            'recording_id' => record.id.to_s, 'call_session_id' => source_call.id.to_s,
                                            'can_link' => true, 'already_linked' => false)
    expect(response.headers.fetch('Cache-Control')).to include('private', 'no-store')
    expect(response.body).not_to include(contact.name, 'contact_id', 'recording_reference', 'synthetic-password')
    expect(source_call.reload.contact_id).to be_nil
    expect(link_audits).to be_empty
    expect(provider).not_to have_received(:find_analysis)
  end

  it 'links the selected covered native contact and company atomically without changing existing call fields or records' do
    before = source_call.reload.attributes.except('contact_id', 'company_id', 'lock_version', 'updated_at')
    contact
    initial_count = account.contacts.count
    write_link
    expect(response).to have_http_status(:ok)
    expect(source_call.reload).to have_attributes(contact_id: contact.id, company_id: company.id)
    expect(source_call.attributes.except('contact_id', 'company_id', 'lock_version', 'updated_at')).to eq(before)
    expect(account.contacts.count).to eq(initial_count)
    audit = link_audits.sole
    expect(audit).to have_attributes(user_id: actor.id, auditable_id: source_call.id, auditable_type: source_call.class.name)
    expect(audit.audited_changes.fetch('before')).to include('contact_id' => nil, 'company_id' => nil)
    expect(audit.audited_changes.fetch('after')).to include('contact_id' => contact.id, 'company_id' => company.id)
  end

  it 'does not replace the initial link or duplicate its audit when the identical request is repeated' do
    original = input.deep_dup
    write_link(original)
    expect(response).to have_http_status(:ok)
    write_link(original)
    expect(response).to have_http_status(:conflict)
    expect(source_call.reload.contact_id).to eq(contact.id)
    expect(link_audits.count).to eq(1)
  end

  it 'protects the persisted event through the real native audit API even for a restricted administrator' do
    account.enable_features!('audit_logs')
    role.update!(permissions: role.permissions + ['jrc_contact_center_audit'])
    write_link
    expect(response).to have_http_status(:ok)
    audit = link_audits.sole
    member.update!(role: :administrator)
    get "/api/v1/accounts/#{account.id}/audit_logs", headers: actor.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('audit_logs').pluck('id').map(&:to_s)).to include(audit.id.to_s)
    role.update!(permissions: role.permissions - ['jrc_contact_center_operate'])
    get "/api/v1/accounts/#{account.id}/audit_logs", headers: actor.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('audit_logs').pluck('id').map(&:to_s)).not_to include(audit.id.to_s)
    expect(audit.reload.id).to be_present
  end

  it 'returns already-linked state without allowing a later replacement' do
    source_call.update!(contact: contact, company: company)
    get path, headers: actor.create_new_auth_token
    expect(response.parsed_body).to include('can_link' => false, 'already_linked' => true)
    write_link
    expect(response).to have_http_status(:conflict)
    expect(link_audits).to be_empty
  end

  [false, 'true', nil].each do |confirmation|
    it "requires explicit Boolean confirmation rather than #{confirmation.inspect}" do
      write_link(input.merge('confirm' => confirmation))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(source_call.reload.contact_id).to be_nil
      expect(link_audits).to be_empty
    end
  end

  [{ 'call_id' => 'SYNTHETIC other external call' }, { 'call_session_id' => '999999' },
   { 'contact_id' => '9223372036854775808' }, { 'contact_id' => '1x' },
   { 'contact_id' => nil }, { 'lock_version' => -1 }, { 'lock_version' => '0' }].each do |invalid|
    it "rejects malformed or mismatching source values #{invalid.inspect}" do
      write_link(input.merge(invalid))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(source_call.reload.contact_id).to be_nil
      expect(link_audits).to be_empty
    end
  end

  %w[jrc_contact_center_recordings_listen jrc_contact_center_operate contact_manage].each do |right|
    it "rechecks the current #{right} authority before linking" do
      original = input
      role.update!(permissions: role.permissions - [right])
      write_link(original)
      expect(response).to have_http_status(:forbidden)
      expect(source_call.reload.contact_id).to be_nil
      expect(link_audits).to be_empty
    end
  end

  it 'does not obtain missing recording authority from administrator status' do
    member.update!(role: :administrator)
    role.update!(permissions: role.permissions - ['jrc_contact_center_recordings_listen'])
    write_link
    expect(response).to have_http_status(:forbidden)
    expect(source_call.reload.contact_id).to be_nil
  end

  it 'rejects a foreign-account contact without accepting account or actor parameters as a grant' do
    foreign = create(:contact, account: create(:account))
    write_link(input.merge('contact_id' => foreign.id.to_s, 'account_id' => foreign.account_id, 'user_id' => actor.id))
    expect(response).to have_http_status(:not_found)
    expect(source_call.reload.contact_id).to be_nil
    expect(link_audits).to be_empty
  end

  it 'rejects a same-account contact whose company is outside the current corporate coverage' do
    hidden_company = account.master_companies.create!(name: 'SYNTHETIC uncovered customer company', relationship_type: 'internal')
    hidden = create(:contact, account: account, company: hidden_company)
    write_link(input.merge('contact_id' => hidden.id.to_s))
    expect(response).to have_http_status(:not_found)
    expect(source_call.reload.contact_id).to be_nil
    expect(link_audits).to be_empty
  end

  it 'rejects a recording after its source unit becomes inaccessible' do
    original = input
    account.jrc_crm_user_business_units.where(user: actor).find_each { |link| link.update!(active: false) }
    write_link(original)
    expect(response).to have_http_status(:not_found)
    expect(source_call.reload.contact_id).to be_nil
  end

  it 'requires a current call version and preserves another committed observation' do
    original = input
    source_call.update!(metadata: source_call.metadata.merge('attendance_observations' => { 'text' => 'SYNTHETIC saved note' }))
    write_link(original)
    expect(response).to have_http_status(:conflict)
    expect(source_call.reload.contact_id).to be_nil
    expect(source_call.metadata.dig('attendance_observations', 'text')).to eq('SYNTHETIC saved note')
  end

  it 'preserves an explicit existing company rather than rebinding it to a selected person' do
    existing_company = account.master_companies.create!(name: 'SYNTHETIC existing call company')
    source_call.update!(company: existing_company)
    write_link
    expect(response).to have_http_status(:conflict)
    expect(source_call.reload).to have_attributes(contact_id: nil, company_id: existing_company.id)
    expect(link_audits).to be_empty
  end

  it 'requires authentication rather than trusting the selected account and contact' do
    post path, params: { customer_link: input }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(source_call.reload.contact_id).to be_nil
  end

  it 'reports unavailable native recording access without returning a successful preview or partially linking a contact' do
    original = input
    account.sip_credentials.where(user: actor).find_each { |credential| credential.update!(enabled: false) }
    get path, headers: actor.create_new_auth_token
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to eq('error' => 'recording_contact_link_source_unavailable')
    write_link(original)
    expect(response).to have_http_status(:service_unavailable)
    expect(source_call.reload.contact_id).to be_nil
    expect(link_audits).to be_empty
  end

  %w[jrc_contact_center jrc_customer_master].each do |feature|
    it "requires the current native #{feature} feature without activating it as part of the request" do
      original = input
      account.disable_features!(feature)
      write_link(original)
      expect(response).to have_http_status(:forbidden)
      expect(source_call.reload.contact_id).to be_nil
      expect(link_audits).to be_empty
    end
  end
end
