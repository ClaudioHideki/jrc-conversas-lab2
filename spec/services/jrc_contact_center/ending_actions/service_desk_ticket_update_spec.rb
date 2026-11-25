require 'rails_helper'

# Native effects only. Rule activation, CC idempotence receipts and F10-B remain
# separate requirements; these examples must never be counted as those proofs.
RSpec.describe JrcContactCenter::EndingActions::ServiceDeskTicketUpdate do
  include_context 'with native ending execution original evidence'
  include_context 'with native ending attempt operators'
  include_context 'JRC Service Desk domain'

  let(:operator) { attempt_operator }
  let(:customer) { account.master_companies.create!(name: 'SYNTHETIC linked SD update customer') }
  let(:contact) { create(:contact, account: account, company_id: customer.id, name: 'SYNTHETIC linked update requester') }
  let(:sd_account) { account }
  let(:sd_user) { operator.user }
  let(:sd_account_user) { operator }
  let(:sd_contact) { contact }
  let(:parameters) do
    { 'ticket_id' => ticket.id.to_s, 'expected_lock_version' => ticket.lock_version,
      'attributes' => { 'title' => 'SYNTHETIC revised native ticket' } }
  end
  let(:ticket) do
    JrcContactCenter::EndingActions::ServiceDeskTicketDestination.new(account: account, member: operator).call(
      origin: reference, request_key: SecureRandom.uuid,
      parameters: { 'unit_id' => sd_unit.id.to_s, 'service_id' => nil,
                    'attributes' => { 'title' => 'SYNTHETIC original linked ticket',
                                      'status_id' => sd_status.id.to_s, 'priority_id' => sd_priority.id.to_s } }
    )
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
    raise 'Owned native linked-ticket update database required' unless owned

    example.run
  end

  before do
    account.enable_features!('jrc_customer_master')
    business.update!(settings: business.settings.merge('service_desk_unit_id' => sd_unit.id.to_s))
  end

  def update_native_ticket(input = parameters, reader = operator)
    described_class.new(account: account, member: reader).call(origin: reference, parameters: input)
  end

  it 'updates the linked native ticket and records the original actor without completing ACW' do
    version = ticket.lock_version
    result = update_native_ticket
    expect(result.fetch(:changed)).to be true
    expect(ticket.reload).to have_attributes(title: parameters.fetch('attributes').fetch('title'), lock_version: version + 1,
                                             requester_id: contact.id, company_id: customer.id)
    event = ticket.ticket_events.where(event_type: 'ticket_updated').sole
    expect(event.actor_membership_id).to eq(sd_membership.id)
    expect(event.data.dig('origin', 'account_user_id')).to eq(operator.id)
    expect(JrcContactCenter::Qualification.find(reference.source_qualification_id).completed_at).to be_nil
    expect(JrcContactCenter::EndingActionExecution.where(account: account)).to be_empty
  end

  it 'treats a native no-op as unchanged without manufacturing another audit event' do
    input = parameters.deep_merge('attributes' => { 'title' => ticket.title })
    result = update_native_ticket(input)
    expect(result.fetch(:changed)).to be false
    expect(ticket.reload.lock_version).to eq(input.fetch('expected_lock_version'))
    expect(ticket.ticket_events.where(event_type: 'ticket_updated')).to be_empty
  end

  it 'rejects a stale explicit version after the first real update without repeating the event' do
    input = parameters
    update_native_ticket(input)
    expect { update_native_ticket(input) }.to raise_error(ActiveRecord::StaleObjectError)
    expect(ticket.ticket_events.where(event_type: 'ticket_updated').count).to eq(1)
    expect(JrcServiceDesk::Ticket.where(account: account).count).to eq(1)
  end

  it 'refuses a ticket whose requester no longer matches the immutable attendance customer' do
    input = parameters
    other = create(:contact, account: account, name: 'SYNTHETIC other linked requester')
    ticket.update!(requester: other)
    expect { update_native_ticket(input) }.to raise_error do |error|
      expect(error.code).to eq('ending_service_desk_customer_link_changed')
    end
    expect(ticket.reload.title).to eq('SYNTHETIC original linked ticket')
  end

  it 'does not reveal or edit another accounts ticket through a numeric target ID' do
    foreign = create(:jrc_sd_ticket, unit: sd_foreign_unit, title: 'SYNTHETIC foreign linked ticket')
    input = parameters.merge('ticket_id' => foreign.id.to_s)
    expect { update_native_ticket(input) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(ticket.reload.title).to eq('SYNTHETIC original linked ticket')
    expect(ticket.ticket_events.where(event_type: 'ticket_updated')).to be_empty
    expect(foreign.reload.title).to eq('SYNTHETIC foreign linked ticket')
  end

  it 'requires the current explicit operational SD membership' do
    input = parameters
    sd_membership.update!(active: false)
    expect { update_native_ticket(input) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(ticket.reload.title).to eq('SYNTHETIC original linked ticket')
  end

  it 'does not treat read access as the native edit permission' do
    input = parameters
    account.enable_features!('custom_roles')
    permissions = %w[contact_manage jrc_contact_center_view jrc_contact_center_operate jrc_service_desk_module_view
                     jrc_service_desk_tickets_view jrc_service_desk_customers_view]
    operator.update!(custom_role: create(:custom_role, account: account, permissions: permissions))
    context = { account: account, account_user: operator, user: operator.user }
    visible = JrcServiceDesk::FindTicketService.new(user_context: context).call(ticket_id: ticket.id)
    expect(visible.id).to eq(ticket.id)
    expect(JrcServiceDesk::TicketPolicy.new(context, visible).update?).to be false
    expect { update_native_ticket(input) }.to raise_error(Pundit::NotAuthorizedError)
    expect(ticket.reload.title).to eq('SYNTHETIC original linked ticket')
  end

  it 'does not borrow the configuration administrators identity' do
    input = parameters
    expect { update_native_ticket(input, member) }.to raise_error(Pundit::NotAuthorizedError)
    expect(ticket.reload.title).to eq('SYNTHETIC original linked ticket')
  end

  it 'refuses a changed native source-to-SD mapping before mutation' do
    input = parameters
    business.update!(settings: business.settings.merge('service_desk_unit_id' => sd_other_unit.id.to_s))
    expect { update_native_ticket(input) }.to raise_error do |error|
      expect(error.code).to eq('ending_service_desk_mapping_changed')
    end
    expect(ticket.reload.title).to eq('SYNTHETIC original linked ticket')
  end

  it 'rolls back the real native edit when PostgreSQL rejects its audit insertion' do
    input = parameters
    ApplicationRecord.connection.execute(<<~SQL.squish)
      CREATE FUNCTION pg_temp.cc_ending_update_audit_reject() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NEW.account_id = #{Integer(account.id)} AND NEW.event_type = 'ticket_updated' THEN
          RAISE EXCEPTION 'SYNTHETIC native update audit rejection';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER cc_ending_update_audit_reject BEFORE INSERT ON jrc_service_desk_ticket_events
        FOR EACH ROW EXECUTE FUNCTION pg_temp.cc_ending_update_audit_reject();
    SQL
    expect do
      ApplicationRecord.transaction(requires_new: true) { update_native_ticket(input) }
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(ticket.reload).to have_attributes(title: 'SYNTHETIC original linked ticket', lock_version: input.fetch('expected_lock_version'))
    expect(ticket.ticket_events.where(event_type: 'ticket_updated')).to be_empty
  end

  it 'rolls back the ticket and native update event with a rejected outer CC receipt transaction' do
    input = parameters
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        update_native_ticket(input)
        raise JrcContactCenter::OperationError, 'SYNTHETIC rejected outer receipt'
      end
    end.to raise_error(JrcContactCenter::OperationError)
    expect(ticket.reload).to have_attributes(title: 'SYNTHETIC original linked ticket', lock_version: input.fetch('expected_lock_version'))
    expect(ticket.ticket_events.where(event_type: 'ticket_updated')).to be_empty
  end

  it 'rechecks the native module flag after command construction' do
    input = parameters
    command = described_class.new(account: account, member: operator)
    account.disable_features!('jrc_service_desk')
    expect { command.call(origin: reference, parameters: input) }.to raise_error(Pundit::NotAuthorizedError)
    expect(ticket.reload.title).to eq('SYNTHETIC original linked ticket')
  end
end
