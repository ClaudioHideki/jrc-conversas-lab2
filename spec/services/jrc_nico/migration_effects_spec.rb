require 'rails_helper'

RSpec.describe 'NICO pending migration effects and domain projections' do
  include_context 'JRC Service Desk domain'
  let(:access) { JrcNico::OperationalAccess.new(account: sd_account, user: sd_user).authorize! }
  let(:session) { JrcNico::Session.create!(account: sd_account, user: sd_user) }
  let(:command) { session.commands.create!(request_id: SecureRandom.uuid, message: 'Synthetic pending migration gate') }
  let(:executor) { JrcNico::ToolExecutor.new(access, command: command) }
  let(:campaign) { sd_account.jrc_campaigns.create!(name: 'Synthetic audience', created_by: sd_user, audience_type: 'all_contacts') }

  before do
    sd_as_admin!
    sd_account.update!(custom_attributes: { 'nico_enabled' => true })
    sd_account.enable_features!('jrc_campaigns', 'jrc_projects')
    batch = JrcMigrations::Batch.create!(account: sd_account, created_by: sd_user, source: 'nico_effect', domain: 'contacts', source_digest: 'a' * 64)
    JrcMigrations::Mapping.create!(account: sd_account, batch: batch, source: 'nico_effect', domain: 'contacts', legacy_id: 'one',
      target_id: sd_contact.id, source_digest: 'a' * 64, target_digest: 'b' * 64, source_updated_at: Time.current)
  end

  it 'omits requester lookup and ticket DTOs which refer to pending contacts' do
    ticket = sd_ticket
    lookup = executor.call('service_desk_lookup', { 'resource' => 'requesters', 'unit_id' => sd_unit.id })
    expect(lookup[:items]).to be_empty
    expect(executor.call('list_service_tickets', {})[:items]).to be_empty
    expect(JrcServiceDesk::TicketQuery.new(user_context: sd_context).collection[:items]).to include(ticket)
  end

  it 'does not invoke a native create service for a pending requester' do
    expect(JrcServiceDesk::CreateTicketWorkflowService).not_to receive(:new)
    expect do
      executor.call('create_service_ticket', sd_create_attributes.stringify_keys.merge('unit_id' => sd_unit.id))
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'does not project a direct record result retained before acceptance changes' do
    expect do
      JrcNico::ToolResultProjection.new(access, account: sd_account).record_result(sd_contact, 'Synthetic', 'contacts_dashboard_index')
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'blocks launch before the native campaign can resolve a pending audience' do
    campaign
    expect_any_instance_of(JrcCampaigns::Campaign).not_to receive(:launch!)
    expect do
      executor.call('campaign_action', { 'campaign_id' => campaign.id, 'action' => 'launch' })
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'does not expose a campaign review snapshot with a pending audience' do
    campaign.update_columns(review_snapshot: { 'recipients' => [{ 'contact_id' => sd_contact.id, 'name' => 'Pending retained snapshot' }] })
    expect(executor.call('list_campaigns', {})).to be_empty
    expect(sd_account.jrc_campaigns.find(campaign.id).review_snapshot).not_to be_empty
  end

  it 'blocks a campaign report before its recipient details or totals are read' do
    campaign
    expect(JrcCampaigns::ReportService).not_to receive(:new)
    expect do
      executor.call('campaign_report', { 'campaign_id' => campaign.id })
    end.to raise_error(ActiveRecord::RecordNotFound)
  end
end
