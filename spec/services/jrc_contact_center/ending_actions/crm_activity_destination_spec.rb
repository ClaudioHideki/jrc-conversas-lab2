require 'rails_helper'

RSpec.describe JrcContactCenter::EndingActions::CrmActivityDestination do
  include_context 'with native ending execution original evidence'
  include_context 'with native ending attempt operators'

  let(:operator) { attempt_operator }
  let(:customer) { account.master_companies.create!(name: 'SYNTHETIC CRM activity customer') }
  let(:contact) { create(:contact, account: account, company_id: customer.id, name: 'SYNTHETIC CRM activity contact') }
  let(:parameters) { { 'activity_type' => 'call', 'title' => 'SYNTHETIC confirmed contact', 'description' => 'SYNTHETIC explicit result' } }
  let(:trigger_at) { Time.zone.parse('2026-11-24 12:30:00') }
  let(:command) { described_class.new(account: account, member: operator) }
  let(:reference) do
    call = new_origin_source_call
    call.update!(contact_id: contact.id, company_id: customer.id)
    JrcContactCenter::CallLeg.create!(account: account, call_session: call, account_user: operator, queue: queue,
                                      direction: 'inbound', status: 'connected', started_at: call.started_at, answered_at: call.answered_at)
    call.update!(status: 'ended', ended_at: Time.current)
    qualification = JrcContactCenter::Qualification.find_by!(account: account, call_session: call, account_user: operator)
    JrcContactCenter::EndingActionOrigin.find_by!(account: account, source_qualification_id: qualification.id)
  end

  around do |example|
    config = ApplicationRecord.connection_db_config
    databases = %w[jrc_sd_bc_portal_concurrency_20261025_test corporate_gratuity_disposable]
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            databases.include?(ApplicationRecord.connection.current_database)
    raise 'Owned native CRM activity database required' unless owned

    example.run
  end

  before do
    account.enable_features!('jrc_crm', 'jrc_customer_master')
    operator.update!(crm_enabled: true)
  end

  it 'records a completed native activity and audit under the original agent without completing ACW' do
    row = reference
    account.disable_features!('jrc_broker')
    activity = command.call(origin: row, parameters: parameters, trigger_at: trigger_at)
    expect(activity).to have_attributes(account_id: account.id, user_id: operator.user_id, contact_id: contact.id,
                                        company_id: customer.id, status: 'completed', completed_at: trigger_at, due_at: trigger_at)
    expect(activity.lead.owner_id).to eq(operator.user_id)
    event = JrcCrm::AuditEvent.where(
      account: account, resource_type: activity.class.name, resource_id: activity.id, event_type: 'activity_created'
    ).sole
    expect([event.actor_type, event.actor_id]).to eq([operator.user.class.name, operator.user_id])
    expect(JrcContactCenter::Qualification.find(row.source_qualification_id).completed_at).to be_nil
    expect(JrcContactCenter::EndingActionExecution.where(account: account)).to be_empty
    expect(account.feature_enabled?('jrc_broker')).to be false
  end

  it 'rolls back the Lead, native activity and audits with the callers receipt transaction' do
    row = reference
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        command.call(origin: row, parameters: parameters, trigger_at: trigger_at)
        raise JrcContactCenter::OperationError, 'SYNTHETIC outer receipt rejection'
      end
    end.to raise_error(JrcContactCenter::OperationError)
    expect(account.jrc_crm_leads.where(contact: contact)).to be_empty
    expect(account.jrc_crm_activities.where(contact: contact)).to be_empty
    expect(JrcCrm::AuditEvent.where(account: account, event_type: %w[lead_created activity_created])).to be_empty
  end

  it 'revalidates the agents CRM flag even on a command constructed before revocation' do
    row = reference
    pending = command
    operator.update!(crm_enabled: false)
    expect { pending.call(origin: row, parameters: parameters, trigger_at: trigger_at) }.to raise_error(Pundit::NotAuthorizedError)
    expect(account.jrc_crm_activities).to be_empty
  end

  it 'revalidates a restrictive native role rather than using the CRM flag as a grant' do
    role = create(:custom_role, account: account, name: 'SYNTHETIC CRM activity role',
                                permissions: %w[contact_manage jrc_crm jrc_contact_center_view jrc_contact_center_operate])
    operator.update!(custom_role: role)
    row = reference
    pending = command
    role.update!(permissions: role.permissions - ['jrc_crm'])
    expect(operator.reload.crm_enabled?).to be true
    expect { pending.call(origin: row, parameters: parameters, trigger_at: trigger_at) }.to raise_error(Pundit::NotAuthorizedError)
    expect(account.jrc_crm_activities).to be_empty
  end

  it 'refuses an origin from another account without creating a native record' do
    row = reference
    other = create(:account)
    foreign = described_class.new(account: other, member: operator)
    expect { foreign.call(origin: row, parameters: parameters, trigger_at: trigger_at) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(other.jrc_crm_activities).to be_empty
    expect(account.jrc_crm_activities).to be_empty
  end

  it 'does not substitute the configuration administrator for the agent attested by the call' do
    row = reference
    administrator = described_class.new(account: account, member: member)
    expect { administrator.call(origin: row, parameters: parameters, trigger_at: trigger_at) }.to raise_error(Pundit::NotAuthorizedError)
    expect(account.jrc_crm_activities).to be_empty
  end

  it 'refuses another native CRM owners Lead without creating a second Lead or activity' do
    row = reference
    account.jrc_crm_leads.create!(owner: actor, contact: contact, name: 'SYNTHETIC other activity owner')
    expect { command.call(origin: row, parameters: parameters, trigger_at: trigger_at) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(account.jrc_crm_leads.where(contact: contact).count).to eq(1)
    expect(account.jrc_crm_activities).to be_empty
  end

  it 'uses only the visible Leads unit and adds no corporate coverage for the original agent' do
    row = reference
    JrcCrm::UserBusinessUnit.where(account: account, user: operator.user).sole.update!(
      scope: 'BUSINESS_UNIT', company_id: issuer.id, business_unit_id: business.id
    )
    account.jrc_crm_leads.create!(
      owner: operator.user, contact: contact, business_unit_id: business.id, name: 'SYNTHETIC visible activity Lead'
    )
    activity = command.call(origin: row, parameters: parameters, trigger_at: trigger_at)
    expect(activity.business_unit_id).to eq(business.id)
    visible = JrcCrm::OrganizationalVisibility.new(account: account, user: operator.user, relation: account.jrc_crm_activities).call
    expect(visible.find(activity.id)).to eq(activity)
    expect(JrcCrm::UserBusinessUnit.where(account: account, user: operator.user).pluck(:scope)).to eq(['BUSINESS_UNIT'])
  end

  it 'requires the real native creation audit and rolls back a new Lead when that dependency fails' do
    row = reference
    allow(JrcCrm::AuditLoggerService).to receive(:new).and_call_original
    logger = instance_double(JrcCrm::AuditLoggerService, call: nil)
    allow(JrcCrm::AuditLoggerService).to receive(:new).with(hash_including(event_type: 'activity_created')).and_return(logger)
    operation = proc do
      ApplicationRecord.transaction(requires_new: true) { command.call(origin: row, parameters: parameters, trigger_at: trigger_at) }
    end
    expect(&operation).to(raise_error { |error| expect(error.code).to eq('ending_crm_native_audit_missing') })
    expect(account.jrc_crm_leads.where(contact: contact)).to be_empty
    expect(account.jrc_crm_activities.where(contact: contact)).to be_empty
  end

  it 'rolls back the entire native operation on an actual PostgreSQL audit insertion rejection' do
    row = reference
    ApplicationRecord.connection.execute(<<~SQL.squish)
      CREATE FUNCTION pg_temp.cc_ending_activity_audit_reject() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NEW.account_id = #{Integer(account.id)} AND NEW.event_type = 'activity_created' THEN
          RAISE EXCEPTION 'SYNTHETIC activity audit rejection';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER cc_ending_activity_audit_reject BEFORE INSERT ON jrc_crm_audit_events
        FOR EACH ROW EXECUTE FUNCTION pg_temp.cc_ending_activity_audit_reject();
    SQL
    expect do
      ApplicationRecord.transaction(requires_new: true) { command.call(origin: row, parameters: parameters, trigger_at: trigger_at) }
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(account.jrc_crm_leads.where(contact: contact)).to be_empty
    expect(JrcCrm::Activity.where(account_id: account.id)).to be_empty
    expect(JrcCrm::AuditEvent.where(account: account, event_type: %w[lead_created activity_created])).to be_empty
  end

  it 'does not fabricate a timestamp when the immutable execution trigger is absent' do
    row = reference
    expect { command.call(origin: row, parameters: parameters, trigger_at: nil) }.to raise_error do |error|
      expect(error.code).to eq('ending_action_trigger_pending')
    end
    expect(account.jrc_crm_activities).to be_empty
  end

  it 'refuses a call whose customer identity was changed after the original capture' do
    row = reference
    JrcContactCenter::CallSession.where(account: account).find(row.call_session_id).update!(contact_id: nil)
    expect { command.call(origin: row, parameters: parameters, trigger_at: trigger_at) }.to raise_error do |error|
      expect(error.code).to eq('ending_customer_reference_changed')
    end
    expect(account.jrc_crm_activities).to be_empty
  end
end
