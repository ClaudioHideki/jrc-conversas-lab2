require 'rails_helper'

RSpec.describe JrcCustomers::OperationalContacts do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, name: 'Operational person') }
  let(:query) { described_class.new(account: account, actor: actor) }

  before { account.enable_features!('jrc_customer_master', 'jrc_crm') }

  it 'does not treat registry activity timestamps, online presence or private notes as operational interaction' do
    contact.update!(last_activity_at: Time.current)
    conversation = create(:conversation, account: account, contact: contact, status: :resolved)
    create(:message, account: account, conversation: conversation, message_type: :outgoing, private: true, content: 'PRIVATE_NOTE_CANARY')
    expect(query.call[:payload]).to be_empty
    expect(query.call[:meta][:total]).to eq(0)
  end

  it 'projects open and waiting source contexts, keeps canonical IDs and deduplicates multiple conversations' do
    first = create(:conversation, account: account, contact: contact, status: :open, assignee: actor)
    create(:conversation, account: account, contact: contact, status: :snoozed)
    waiting = create(:contact, account: account)
    create(:conversation, account: account, contact: waiting, status: :pending)
    result = query.call
    expect(result[:meta][:total]).to eq(2)
    row = result[:payload].find { |item| item['id'] == contact.id }
    expect(row).to include('operational_status' => 'in_service', 'last_interaction_at' => nil)
    expect(row['context']).to include('kind' => 'conversation')
    expect(result.to_json).not_to include('content_attributes', 'custom_attributes', 'access_token')
    expect(query.call(params: { status: 'waiting' })[:payload].pluck('id')).to eq([waiting.id])
    expect(first.reload.status).to eq('open')
  end

  it 'uses a configurable recent window of authorized public messages without returning their bodies' do
    conversation = create(:conversation, account: account, contact: contact, status: :resolved)
    message = create(:message, account: account, conversation: conversation, content: 'MESSAGE_BODY_CANARY', created_at: 12.days.ago)
    conversation.resolved!
    expect(query.call(params: { days: 10 })[:payload]).to be_empty
    row = query.call(params: { days: 20 })[:payload].sole
    expect(row).to include('id' => contact.id, 'operational_status' => 'active')
    expect(Time.parse(row['last_interaction_at'].to_s).to_i).to eq(message.created_at.to_i)
    expect(row['context']).to include('record_id' => conversation.id, 'display_id' => conversation.display_id, 'state' => 'resolved')
    expect(row.to_json).not_to include('MESSAGE_BODY_CANARY')
  end

  it 'never activates or discloses an invisible inbox even if the directory timestamp is recent' do
    membership = account.account_users.find_by!(user: actor)
    membership.update!(role: :agent)
    inbox = create(:channel_api, account: account).inbox
    conversation = create(:conversation, account: account, contact: contact, inbox: inbox, status: :open)
    create(:message, account: account, conversation: conversation, content: 'HIDDEN_MESSAGE')
    expect(query.call[:payload]).to be_empty
    create(:inbox_member, inbox: inbox, user: actor)
    expect(query.call[:payload].pluck('id')).to eq([contact.id])
  end

  it 'applies Enterprise conversation participating permissions afresh to both items and totals' do
    inbox = create(:channel_api, account: account).inbox
    create(:inbox_member, inbox: inbox, user: actor)
    role = create(:custom_role, account: account, permissions: %w[contact_manage conversation_participating_manage])
    account.account_users.find_by!(user: actor).update!(role: :agent, custom_role: role)
    conversation = create(:conversation, account: account, contact: contact, inbox: inbox, status: :open)
    expect(query.call[:meta][:total]).to eq(0)
    create(:conversation_participant, account: account, conversation: conversation, user: actor)
    expect(query.call[:meta][:total]).to eq(1)
    role.update!(permissions: ['contact_manage'])
    expect(query.call[:meta][:total]).to eq(0)
  end

  it 'uses only visible CRM activities and their true pending state, excluding completed and cancelled tasks' do
    account.account_users.find_by!(user: actor).update!(role: :agent)
    lead = account.jrc_crm_leads.create!(name: 'Native lead', owner: actor, contact: contact)
    activity = account.jrc_crm_activities.create!(user: actor, lead: lead, title: 'Next real action', activity_type: 'call', due_at: 1.day.ago)
    row = query.call[:payload].sole
    expect(row['next_action']).to include('kind' => 'activity', 'record_id' => activity.id, 'title' => activity.title)
    expect(row['next_action']['responsible']).to include(id: actor.id, name: actor.name)
    activity.update!(status: 'cancelled')
    expect(query.call[:payload]).to be_empty
    activity.update!(status: 'completed', completed_at: 40.days.ago)
    expect(query.call[:payload]).to be_empty
    expect(query.call(params: { days: 50 })[:payload].sole['next_action']).to be_nil
    activity.update!(status: 'scheduled', completed_at: nil)
    role = create(:custom_role, account: account, permissions: ['contact_manage'])
    account.account_users.find_by!(user: actor).update!(custom_role: role)
    expect(query.call[:payload]).to be_empty
  end

  it 'resolves legacy pending actions only through visible linked origins and preserves their native identifiers' do
    lead = account.jrc_crm_leads.create!(name: 'Native lead', owner: actor, contact: contact)
    action = account.jrc_crm_follow_ups.create!(user: actor, lead: lead, title: 'Legacy follow-up', due_at: 1.day.from_now)
    row = query.call[:payload].sole
    expect(row['next_action']).to include('kind' => 'follow_up', 'record_id' => action.id)
    action.update!(is_completed: true, completed_at: 50.days.ago)
    expect(query.call[:payload]).to be_empty
  end

  it 'isolates accounts and corporate coverage without trusting caller tenant, user or unit parameters' do
    foreign = create(:contact)
    create(:conversation, account: foreign.account, contact: foreign, status: :open)
    issuer = account.master_companies.create!(name: 'Allowed operator', relationship_type: 'internal')
    hidden = account.master_companies.create!(name: 'HIDDEN_OPERATOR', relationship_type: 'internal')
    unit = account.jrc_crm_business_units.create!(name: 'Allowed unit', code: 'OPS-A', company_id: issuer.id)
    account.jrc_crm_business_units.create!(name: 'Hidden unit', code: 'OPS-B', company_id: hidden.id)
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: issuer, business_unit: unit, active: true)
    contact.update!(company_id: hidden.id)
    create(:conversation, account: account, contact: contact, status: :open)
    result = query.call(params: { account_id: foreign.account_id, user_id: 0, unit_id: 0, operator_id: hidden.id })
    expect(result[:payload]).to be_empty
    expect(result.to_json).not_to include('HIDDEN_OPERATOR')
  end

  it 'rechecks feature, current membership and custom directory permission on every call' do
    create(:conversation, account: account, contact: contact, status: :open)
    expect(query.call[:meta][:total]).to eq(1)
    account.disable_features!('jrc_customer_master')
    expect { query.call }.to raise_error(Pundit::NotAuthorizedError)
    account.enable_features!('jrc_customer_master')
    role = create(:custom_role, account: account, permissions: ['jrc_crm'])
    account.account_users.find_by!(user: actor).update!(role: :agent, custom_role: role)
    expect { query.call }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'projects only native calls handled by the agent in visible conversations and never includes transcripts or recording metadata' do
    account.account_users.find_by!(user: actor).update!(role: :agent)
    inbox = create(:channel_api, account: account).inbox
    create(:inbox_member, inbox: inbox, user: actor)
    conversation = create(:conversation, account: account, contact: contact, inbox: inbox, status: :resolved)
    call = create(:call, conversation: conversation, status: 'completed', started_at: Time.current, transcript: 'PRIVATE_CALL_TRANSCRIPT')
    expect(query.call[:payload]).to be_empty
    call.update!(accepted_by_agent: actor)
    row = query.call[:payload].sole
    expect(row['context']).to include('kind' => 'call', 'record_id' => call.id, 'channel_type' => 'phone')
    expect(row.to_json).not_to include('PRIVATE_CALL_TRANSCRIPT', 'provider_call_id', 'recording_sid')
  end

  it 'paginates deterministically, caps the window/page and treats query wildcards literally' do
    3.times do |index|
      person = create(:contact, account: account, name: "Operational #{index}")
      create(:conversation, account: account, contact: person, status: :open)
    end
    first = query.call(params: { per_page: 2 })
    second = query.call(params: { per_page: 2, page: 2 })
    expect(first[:meta]).to include(total: 3, per_page: 2)
    expect(second[:payload].size).to eq(1)
    expect(first[:payload].pluck('id') & second[:payload].pluck('id')).to be_empty
    expect(query.call(params: { per_page: 999, days: 999 })[:meta]).to include(per_page: 50, days: 365)
    expect(query.call(params: { q: '%' })[:payload]).to be_empty
    expect { query.call(params: { status: 'invented' }) }.to raise_error(ActionController::BadRequest)
    expect { query.call(params: { kind: 'private_notes' }) }.to raise_error(ActionController::BadRequest)
  end

  context 'with native Service Desk unit grants' do
    include_context 'JRC Service Desk domain'
    let(:account) { sd_account }
    let(:actor) { sd_user }

    it 'links the true authorized ticket and omits another unit without treating a supplied unit as a grant' do
      ticket = sd_ticket
      hidden = create(:jrc_sd_ticket, unit: sd_other_unit, title: 'PRIVATE_HIDDEN_UNIT_TICKET')
      row = query.call(params: { unit_id: sd_other_unit.id })[:payload].sole
      expect(row).to include('id' => sd_contact.id, 'operational_status' => 'in_service')
      expect(row['context']).to include('kind' => 'ticket', 'record_id' => ticket.id, 'title' => ticket.title)
      expect(query.call.to_json).not_to include(hidden.title)
      sd_membership.update!(active: false)
      expect(query.call[:payload]).to be_empty
    end

    it 'does not expose historical interactions without the native history permission' do
      ticket = sd_ticket
      closed = create(:jrc_sd_status, unit: sd_unit, phase: 'resolved', initial: false)
      ticket.update!(status: closed)
      JrcServiceDesk::TicketEvent.create!(account: account, unit: sd_unit, ticket: ticket, actor_membership: sd_membership,
                                          event_type: 'ticket_updated', data: { secret: 'PRIVATE_TICKET_EVENT' })
      role = create(:custom_role, account: account,
                                  permissions: %w[contact_manage jrc_service_desk_module_view jrc_service_desk_tickets_view
                                                  jrc_service_desk_customers_view])
      sd_account_user.update!(custom_role: role)
      expect(query.call[:payload]).to be_empty
    end
  end
end
