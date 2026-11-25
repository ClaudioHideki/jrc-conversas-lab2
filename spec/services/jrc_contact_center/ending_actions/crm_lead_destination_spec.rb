require 'rails_helper'
require 'stringio'

RSpec.describe JrcContactCenter::EndingActions::CrmLeadDestination do
  include_context 'with native ending execution original evidence'
  include_context 'with native ending attempt operators'

  let(:operator) { attempt_operator }
  let(:customer) { account.master_companies.create!(name: 'SYNTHETIC native CRM destination') }
  let(:contact) { create(:contact, account: account, company_id: customer.id, name: 'SYNTHETIC CRM contact') }
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
    raise 'Owned native CRM destination database required' unless owned

    example.run
  end

  before do
    account.enable_features!('jrc_crm', 'jrc_customer_master')
    operator.update!(crm_enabled: true)
  end

  it 'creates through native CRM with the original nonadministrator contact, company and creation audit' do
    result = described_class.new(account: account, member: operator).call(origin: reference)
    lead = result.fetch(:lead).reload
    expect(result.fetch(:created)).to be true
    expect([lead.account_id, lead.owner_id, lead.contact_id, lead.company_id]).to eq([account.id, operator.user_id, contact.id, customer.id])
    expect(operator.reload.role).to eq('agent')
    event = JrcCrm::AuditEvent.where(account: account, resource_type: lead.class.name, resource_id: lead.id, event_type: 'lead_created').sole
    expect([event.actor_id, event.actor_type]).to eq([operator.user_id, operator.user.class.name])
    expect(JrcContactCenter::EndingActionExecution.where(account: account)).to be_empty
    expect(JrcContactCenter::Qualification.find(reference.source_qualification_id).completed_at).to be_nil
  end

  it 'reuses the same native Lead on repeated calls without another creation or audit' do
    first = described_class.new(account: account, member: operator).call(origin: reference)
    again = described_class.new(account: account, member: operator).call(origin: reference)
    expect(again).to eq(lead: first.fetch(:lead), created: false)
    expect(account.jrc_crm_leads.where(contact: contact).count).to eq(1)
    expect(JrcCrm::AuditEvent.where(account: account, resource_type: first.fetch(:lead).class.name,
                                    resource_id: first.fetch(:lead).id, event_type: 'lead_created').count).to eq(1)
  end

  it 'preserves native audits while keeping customer values out of this commands SQL diagnostics only' do
    row = reference
    contact.update!(name: 'SYNTHETIC private CRM identity', email: 'private-crm@example.invalid', phone_number: '+5511997766554')
    output = StringIO.new
    previous = ActiveRecord::Base.logger
    ActiveRecord::Base.logger = ActiveSupport::Logger.new(output)
    result = described_class.new(account: account, member: operator).call(origin: row)
    ApplicationRecord.connection.execute('SELECT 1 AS synthetic_outside_crm_command')
    expect(output.string).to include('synthetic_outside_crm_command')
    expect(output.string).not_to include(contact.name, contact.email, contact.phone_number)
    expect(result.fetch(:lead).reload.name).to eq(contact.name)
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'lead_created').count).to eq(1)
  ensure
    ActiveRecord::Base.logger = previous
  end

  it 'revalidates current CRM enablement even when the native Lead already exists' do
    first = described_class.new(account: account, member: operator).call(origin: reference)
    operator.update!(crm_enabled: false)
    expect { described_class.new(account: account, member: operator).call(origin: reference) }.to raise_error do |error|
      expect(error.class.name).to eq('Pundit::NotAuthorizedError')
    end
    expect(first.fetch(:lead).reload.owner_id).to eq(operator.user_id)
    expect(account.jrc_crm_leads.where(contact: contact).count).to eq(1)
  end

  it 'does not replace the original actor by the configuration administrator' do
    row = reference
    expect { described_class.new(account: account, member: member).call(origin: row) }.to raise_error do |error|
      expect(error.class.name).to eq('Pundit::NotAuthorizedError')
    end
    expect(account.jrc_crm_leads.where(contact: contact)).to be_empty
  end

  it 'denies a Lead owned by another native CRM actor without creating a duplicate' do
    row = reference
    account.jrc_crm_leads.create!(owner: actor, contact: contact, name: 'SYNTHETIC existing other owner')
    expect { described_class.new(account: account, member: operator).call(origin: row) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(account.jrc_crm_leads.where(contact: contact).count).to eq(1)
  end

  it 'preserves the native ambiguity rejection when several Leads refer to the same authorized contact' do
    row = reference
    2.times { account.jrc_crm_leads.create!(owner: operator.user, contact: contact, name: 'SYNTHETIC ambiguous native lead') }
    expect { described_class.new(account: account, member: operator).call(origin: row) }.to raise_error do |error|
      expect(error.class.name).to eq('JrcCrm::ContactLeadService::AmbiguousContact')
    end
    expect(account.jrc_crm_leads.where(contact: contact).count).to eq(2)
  end

  it 'does not infer or create a Contact for an unidentified source call' do
    row = reference
    JrcContactCenter::CallSession.where(account: account).find(row.call_session_id).update!(contact_id: nil)
    original = account.contacts.count
    expect { described_class.new(account: account, member: operator).call(origin: row) }.to raise_error do |error|
      expect(error.code).to eq('ending_customer_reference_changed')
    end
    expect(account.contacts.count).to eq(original)
    expect(account.jrc_crm_leads.where(contact: contact)).to be_empty
  end

  it 'denies the native CRM operation after the account feature is disabled' do
    row = reference
    account.disable_features!('jrc_crm')
    expect { described_class.new(account: account, member: operator).call(origin: row) }.to raise_error do |error|
      expect(error.class.name).to eq('Pundit::NotAuthorizedError')
    end
    expect(account.jrc_crm_leads.where(contact: contact)).to be_empty
  end

  it 'does not treat a foreign source origin as permission to read or create a Lead' do
    row = reference
    other = create(:account)
    expect { described_class.new(account: other, member: operator).call(origin: row) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(other.jrc_crm_leads).to be_empty
    expect(account.jrc_crm_leads.where(contact: contact)).to be_empty
  end

  it 'preserves the native controller CRM permission after a restrictive profile removes only CRM' do
    role = create(:custom_role, account: account, name: 'SYNTHETIC native CRM module authority',
                                permissions: %w[contact_manage jrc_crm jrc_contact_center_view jrc_contact_center_operate])
    operator.update!(custom_role: role)
    row = reference
    command = described_class.new(account: account, member: operator)
    expect([operator.reload.crm_enabled?, JrcOperations::Access.crm?(operator)]).to eq([true, true])
    role.update!(permissions: role.permissions - ['jrc_crm'])
    identity = JrcContactCenter::EndingActions::OriginalCustomerReference.new(account: account, member: operator, origin: row).call
    expect(identity).to include(contact_id: contact.id, current_company_id: customer.id)
    native = JrcCrm::ContactLeadService.new(account: account, actor: operator.user, contact_id: contact.id)
    expect(native.call(create: false)).to eq(lead: nil, created: false)
    expect(JrcOperations::Access.crm?(JrcOperations::Access.refresh(operator))).to be false
    expect { command.call(origin: row) }.to raise_error(Pundit::NotAuthorizedError)
    expect(account.jrc_crm_leads.where(contact: contact)).to be_empty
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'lead_created')).to be_empty
  end

  it 'rolls back the native Lead when its native creation audit is not persisted' do
    row = reference
    # Deliberate dependency persistence fault, not the success-path evidence.
    allow(JrcCrm::AuditEvent).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'SYNTHETIC audit failure')
    failure = nil
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        described_class.new(account: account, member: operator).call(origin: row)
      end
    end.to(raise_error { |error| failure = error })
    expect([failure.class.name, failure.code]).to eq(['JrcContactCenter::OperationError', 'ending_crm_native_audit_missing'])
    expect(account.jrc_crm_leads.where(contact: contact)).to be_empty
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'lead_created')).to be_empty
  end

  it 'also rolls back the native Lead on an actual PostgreSQL audit persistence rejection' do
    row = reference
    sql = <<~SQL.squish
      CREATE FUNCTION pg_temp.cc_ending_crm_audit_reject() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NEW.account_id = #{Integer(account.id)} AND NEW.event_type = 'lead_created' THEN
          RAISE EXCEPTION 'SYNTHETIC native CRM audit persistence rejection';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER cc_ending_crm_audit_reject BEFORE INSERT ON jrc_crm_audit_events
        FOR EACH ROW EXECUTE FUNCTION pg_temp.cc_ending_crm_audit_reject();
    SQL
    ApplicationRecord.connection.execute(sql)
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        described_class.new(account: account, member: operator).call(origin: row)
      end
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(account.jrc_crm_leads.where(contact: contact)).to be_empty
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'lead_created')).to be_empty
  end

  def restrict_original_actor_to_source_crm_unit
    JrcCrm::UserBusinessUnit.where(account: account, user: operator.user).sole.update!(
      scope: 'BUSINESS_UNIT', company_id: issuer.id, business_unit_id: business.id
    )
  end

  it 'does not return an owned existing Lead outside the native CRM unit despite an authorized Contact' do
    row = reference
    restrict_original_actor_to_source_crm_unit
    other = JrcCrm::BusinessUnit.create!(
      account: account, operating_company: issuer,
      name: 'SYNTHETIC hidden CRM unit', code: 'CRM_HIDDEN', active: true
    )
    lead = account.jrc_crm_leads.create!(
      owner: operator.user, contact: contact, business_unit_id: other.id, name: 'SYNTHETIC hidden owned native Lead'
    )
    policy = JrcCrm::LeadPolicy.new({ account: account, account_user: operator, user: operator.user }, lead)
    expect(policy.show?).to be true
    visible = JrcCrm::OrganizationalVisibility.new(account: account, user: operator.user, relation: account.jrc_crm_leads).call
    expect(visible.where(id: lead.id)).to be_empty
    native = JrcCrm::ContactLeadService.new(account: account, actor: operator.user, contact_id: contact.id)
    expect(native.call(create: false)).to eq(lead: lead, created: false)
    expect { described_class.new(account: account, member: operator).call(origin: row) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(account.jrc_crm_leads.where(contact: contact).count).to eq(1)
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'lead_created')).to be_empty
  end

  it 'rolls back a new unscoped native Lead rather than invent its unit or return an invisible record' do
    row = reference
    restrict_original_actor_to_source_crm_unit
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        described_class.new(account: account, member: operator).call(origin: row)
      end
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(account.jrc_crm_leads.where(contact: contact)).to be_empty
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'lead_created')).to be_empty
    expect(JrcCrm::UserBusinessUnit.where(account: account, user: operator.user).sole.scope).to eq('BUSINESS_UNIT')
  end
end
