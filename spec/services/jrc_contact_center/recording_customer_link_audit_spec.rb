# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcContactCenter::RecordingCustomerLinkAudit, :pabx do
  include_context 'with native authorized quality review source'

  let(:contact) { create(:contact, account: account, master_company: company, name: 'SYNTHETIC audit-scoped existing contact') }
  let(:context) { { account: account, account_user: member.reload, user: actor.reload } }
  let(:native_audits) { Audited.audit_class.where(associated: account) }
  let(:ordinary) do
    Audited.audit_class.create!(auditable: account, associated: account, user: actor, action: 'update',
                                comment: 'SYNTHETIC unrelated native audit', audited_changes: { 'synthetic' => true })
  end

  before do
    account.enable_features!('jrc_customer_master', 'audit_logs')
    role.update!(permissions: role.permissions + %w[jrc_contact_center_operate jrc_contact_center_audit contact_manage])
    input = { 'contact_id' => contact.id.to_s, 'call_session_id' => source_call.id.to_s,
              'call_id' => record.external_unique_id, 'lock_version' => source_call.reload.lock_version, 'confirm' => true }
    JrcContactCenter::RecordingCustomerLink.new(account: account, member: member).call(record.id, input)
    ordinary
  end

  def link_audit
    native_audits.find_by!(comment: JrcContactCenter::RecordingCustomerLink::COMMENT)
  end

  def protected_native_list
    JrcContactCenter::ConfigurationAuditScope.protect_native_list(native_audits, context)
  end

  it 'retains the authorized native event and independent ordinary audits without exposing provider metadata' do
    expect(protected_native_list).to include(link_audit, ordinary)
    expect(link_audit.audited_changes).not_to have_key('recording_reference')
  end

  %w[jrc_contact_center_audit jrc_contact_center_operate jrc_contact_center_recordings_listen contact_manage].each do |right|
    it "removes the customer-link event from the ordinary account list after current #{right} is revoked" do
      target = link_audit
      role.update!(permissions: role.permissions - [right])
      expect(protected_native_list).not_to include(target)
      expect(protected_native_list).to include(ordinary)
    end
  end

  it 'rechecks the current source unit coverage while preserving the stored event' do
    target = link_audit
    account.jrc_crm_user_business_units.where(user: actor).find_each { |link| link.update!(active: false) }
    expect(protected_native_list).not_to include(target)
    expect(target.reload.id).to be_present
    expect(protected_native_list).to include(ordinary)
  end

  it 'rechecks the native master coverage of the linked person on every read' do
    target = link_audit
    hidden = account.master_companies.create!(name: 'SYNTHETIC uncovered audit company', relationship_type: 'internal')
    contact.update!(master_company: hidden)
    expect(protected_native_list).not_to include(target)
    expect(protected_native_list).to include(ordinary)
  end

  it 'does not use a historical recording right when the personal native SIP association is disabled' do
    target = link_audit
    SipCredential.where(account: account, user: actor).find_each { |credential| credential.update!(enabled: false) }
    expect(protected_native_list).not_to include(target)
    expect(protected_native_list).to include(ordinary)
  end

  it 'keeps the event stored but unavailable when the native master feature is disabled' do
    target = link_audit
    account.disable_features!('jrc_customer_master')
    expect(protected_native_list).not_to include(target)
    expect(protected_native_list).to include(ordinary)
  end
end
