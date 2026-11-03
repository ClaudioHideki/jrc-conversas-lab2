require 'rails_helper'

RSpec.describe 'NICO acceptance of newly registered historical domains' do
  let(:account) { create(:account, custom_attributes: { 'nico_enabled' => true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:unit) { create(:jrc_sd_unit, account: account, operator_company: create(:jrc_sd_operator_company, account: account)) }
  let(:ticket) { create(:jrc_sd_ticket, unit: unit, account: account) }
  let(:project) do
    JrcProjects::Project.create!(account: account, owner: admin, key: 'FILES', name: 'Native project', status: 'planned', visibility: 'account')
  end
  let(:task) do
    JrcProjects::Task.create!(account: account, project: project, created_by: admin, title: 'Native task',
      status: 'backlog', priority: 'medium', estimated_minutes: 0)
  end

  def pending_mapping(record, domain)
    batch = JrcMigrations::Batch.create!(account: account, created_by: admin, source: 'nico_domains', domain: domain, source_digest: 'a' * 64)
    JrcMigrations::Mapping.create!(account: account, batch: batch, source: 'nico_domains', domain: domain, legacy_id: record.id.to_s,
      target_id: record.id, source_digest: 'a' * 64, target_digest: 'b' * 64, source_updated_at: Time.current)
  end

  {
    'service_desk_tickets' => :ticket,
    'service_desk_events' => :event,
    'service_desk_sla_snapshots' => :snapshot,
    'service_desk_sla_milestones' => :milestone
  }.each do |domain, kind|
    it "rejects the #{domain} own mapping while its native parent stays visible" do
      record = case kind
               when :ticket then ticket
               when :event then create(:jrc_sd_event, ticket: ticket)
               when :snapshot then create(:jrc_sd_snapshot, ticket: ticket)
               when :milestone then create(:jrc_sd_milestone, sla_snapshot: create(:jrc_sd_snapshot, ticket: ticket))
               end
      pending_mapping(record, domain)
      expect(JrcNico::MigrationVisibility.scope(record.class, account: account).exists?(id: record.id)).to be(false)
      expect(record.class.exists?(record.id)).to be(true)
      expect(JrcNico::MigrationVisibility.scope(ticket.class, account: account).exists?(id: ticket.id)).to be(true) unless kind == :ticket
    end
  end

  %w[project_attachments project_task_attachments].each do |domain|
    it "checks #{domain} acceptance and typed parent without an Attachment account_id column" do
      parent = domain == 'project_attachments' ? project : task
      blob = ActiveStorage::Blob.create_before_direct_upload!(filename: 'synthetic.txt', content_type: 'text/plain',
        byte_size: 9, checksum: Base64.strict_encode64(Digest::MD5.digest('synthetic')))
      attachment = ActiveStorage::Attachment.create!(record: parent, name: 'attachments', blob: blob)
      pending_mapping(attachment, domain)
      expect do
        JrcNico::MigrationVisibility.authorize!(attachment, account: account)
      end.to raise_error(ActiveRecord::RecordNotFound)
      expect(parent.attachments_attachments.exists?(attachment.id)).to be(true)
    end
  end

  it 'does not project native attachment aggregate counters outside the NICO evidence scope' do
    account.enable_features!('jrc_projects')
    access = JrcNico::OperationalAccess.new(account: account, user: admin).authorize!
    result = JrcNico::DomainActions.new(access).call('read_project', { 'project_id' => project.id })
    expect(result[:record]).not_to have_key('attachments_count')
  end
end
