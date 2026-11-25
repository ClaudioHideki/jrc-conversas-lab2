require 'rails_helper'

# Real native Ticket/events only. These tests do not claim rule dispatch,
# independent CC receipts or the cross-destination F10-B recovery scenario.
RSpec.describe JrcContactCenter::EndingActions::ServiceDeskTicketDestination do
  include_context 'with native ending execution original evidence'
  include_context 'with native ending attempt operators'
  include_context 'JRC Service Desk domain'

  let(:operator) { attempt_operator }
  let(:customer) { account.master_companies.create!(name: 'SYNTHETIC native SD customer') }
  let(:contact) { create(:contact, account: account, company_id: customer.id, name: 'SYNTHETIC native SD requester') }
  let(:sd_account) { account }
  let(:sd_user) { operator.user }
  let(:sd_account_user) { operator }
  let(:sd_contact) { contact }
  let(:request_key) { SecureRandom.uuid }
  let(:parameters) do
    { 'unit_id' => sd_unit.id.to_s, 'service_id' => nil,
      'attributes' => { 'title' => 'SYNTHETIC native ending ticket', 'description' => 'SYNTHETIC private description',
                        'status_id' => sd_status.id.to_s, 'priority_id' => sd_priority.id.to_s } }
  end
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
    raise 'Owned native Service Desk destination database required' unless owned

    example.run
  end

  before do
    account.enable_features!('jrc_customer_master')
    business.update!(settings: business.settings.merge('service_desk_unit_id' => sd_unit.id.to_s))
  end

  def create_native_ticket(row = reference, input = parameters, reader = operator)
    described_class.new(account: account, member: reader).call(origin: row, parameters: input, request_key: request_key)
  end

  it 'creates a native Ticket and audit context using the original nonadministrator requester, company and explicit mapped SD unit' do
    ticket = create_native_ticket
    expect(ticket).to have_attributes(account_id: account.id, unit_id: sd_unit.id, requester_id: contact.id,
                                      company_id: customer.id, created_by_membership_id: sd_membership.id)
    expect(operator.reload.role).to eq('agent')
    expect(ticket.ticket_events.where(event_type: 'ticket_created').sole.actor_membership_id).to eq(sd_membership.id)
    expect(ticket.ticket_events.where(event_type: 'creation_context_recorded').count).to eq(1)
    expect(JrcContactCenter::Qualification.find(reference.source_qualification_id).completed_at).to be_nil
    expect(JrcContactCenter::EndingActionExecution.where(account: account)).to be_empty
  end

  it 'reuses the native ticket and both native context events for the exact same request key' do
    first = create_native_ticket
    again = create_native_ticket
    expect(again.id).to eq(first.id)
    expect(JrcServiceDesk::Ticket.where(account: account, requester: contact).count).to eq(1)
    expect(first.ticket_events.where(event_type: 'ticket_created').count).to eq(1)
    expect(first.ticket_events.where(event_type: 'creation_context_recorded').count).to eq(1)
  end

  it 'revalidates native ticket creation rights even when a ticket already exists for this key' do
    ticket = create_native_ticket
    account.enable_features!('custom_roles')
    permissions = %w[contact_manage jrc_contact_center_view jrc_contact_center_operate jrc_service_desk_module_view]
    role = create(:custom_role, account: account, permissions: permissions)
    operator.update!(custom_role: role)
    expect { create_native_ticket }.to raise_error do |error|
      expect(error.class.name).to eq('Pundit::NotAuthorizedError')
    end
    expect(JrcServiceDesk::Ticket.where(account: account, requester: contact).pluck(:id)).to eq([ticket.id])
  end

  it 'does not borrow the configuration administrator identity for an ordinary original attendance' do
    row = reference
    expect { create_native_ticket(row, parameters, member) }.to raise_error do |error|
      expect(error.class.name).to eq('Pundit::NotAuthorizedError')
    end
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
  end

  it 'requires the current native operational membership in the target SD unit' do
    row = reference
    sd_membership.update!(active: false)
    expect { create_native_ticket(row) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
  end

  it 'does not infer a target unit when the native business-unit mapping is absent' do
    row = reference
    business.update!(settings: business.settings.except('service_desk_unit_id'))
    expect { create_native_ticket(row) }.to raise_error do |error|
      expect(error.code).to eq('ending_service_desk_mapping_required')
    end
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
  end

  it 'refuses a changed native mapping even when the original agent can access both SD units' do
    row = reference
    create(:jrc_sd_membership, unit: sd_other_unit, account_user: operator)
    business.update!(settings: business.settings.merge('service_desk_unit_id' => sd_other_unit.id.to_s))
    expect { create_native_ticket(row) }.to raise_error do |error|
      expect(error.code).to eq('ending_service_desk_mapping_changed')
    end
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
  end

  it 'does not grant access to another accounts unit through a configured numeric ID' do
    row = reference
    input = parameters.merge('unit_id' => sd_foreign_unit.id.to_s)
    expect { create_native_ticket(row, input) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
    expect(JrcServiceDesk::Ticket.where(account: sd_foreign_account)).to be_empty
  end

  it 'rejects a configured requester override before creating any native record' do
    row = reference
    input = parameters.deep_dup
    input['attributes']['requester_id'] = create(:contact, account: sd_foreign_account, name: 'SYNTHETIC forbidden requester').id
    expect { create_native_ticket(row, input) }.to raise_error do |error|
      expect(error.code).to eq('invalid_ending_service_desk_definition')
    end
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
  end

  it 'rolls back the actual native Ticket and creation event when PostgreSQL rejects the native creation context' do
    row = reference
    sql = <<~SQL.squish
      CREATE FUNCTION pg_temp.cc_ending_sd_context_reject() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NEW.account_id = #{Integer(account.id)} AND NEW.event_type = 'creation_context_recorded' THEN
          RAISE EXCEPTION 'SYNTHETIC native ticket context rejection';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER cc_ending_sd_context_reject BEFORE INSERT ON jrc_service_desk_ticket_events
        FOR EACH ROW EXECUTE FUNCTION pg_temp.cc_ending_sd_context_reject();
    SQL
    ApplicationRecord.connection.execute(sql)
    expect do
      ApplicationRecord.transaction(requires_new: true) { create_native_ticket(row) }
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
    expect(JrcServiceDesk::TicketEvent.where(account: account)).to be_empty
  end

  it 'proves the native operational tables share the outer transaction pool instead of assuming cross-database atomicity' do
    expect(JrcServiceDesk::Ticket.connection_pool).to equal(ApplicationRecord.connection_pool)
    expect(JrcServiceDesk::TicketEvent.connection_pool).to equal(ApplicationRecord.connection_pool)
    expect(JrcServiceDesk::Ticket.connection.current_database).to eq(ApplicationRecord.connection.current_database)
  end

  it 'revalidates the original company link before invoking the native ticket workflow' do
    row = reference
    other = account.master_companies.create!(name: 'SYNTHETIC changed customer company')
    contact.update!(company_id: other.id)
    expect { create_native_ticket(row) }.to raise_error do |error|
      expect(error.code).to eq('ending_customer_reference_changed')
    end
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
  end
end
