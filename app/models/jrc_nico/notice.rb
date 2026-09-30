# == Schema Information
#
# Table name: jrc_nico_notices
#
#  id              :bigint           not null, primary key
#  body            :text             not null
#  event_key       :string           not null
#  kind            :string           not null
#  metadata        :jsonb            not null
#  read_at         :datetime
#  request         :text
#  status          :string           default("new"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  conversation_id :bigint
#  user_id         :bigint           not null
#
# Indexes
#
#  index_jrc_nico_notices_on_account_id       (account_id)
#  index_jrc_nico_notices_on_conversation_id  (conversation_id)
#  index_jrc_nico_notices_on_user_id          (user_id)
#  nico_notice_event_once                     (account_id,user_id,event_key) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
class JrcNico::Notice < ApplicationRecord
  self.table_name = 'jrc_nico_notices'
  belongs_to :account
  belongs_to :user
  belongs_to :conversation, optional: true
  has_many :commands, class_name: 'JrcNico::Command', foreign_key: :source_notice_id, dependent: :nullify
  validates :body, presence: true, length: { maximum: 8000 }
  validates :request, length: { maximum: 2000 }
  validates :kind, inclusion: { in: %w[action opportunity handoff result attention] }
  after_create_commit :schedule_action

  def schedule_action
    JrcNico::NoticePlanJob.perform_later(id) if kind == 'action' && request.present?
  end

  def self.publish!(account:, user:, event_key:, **attributes)
    find_or_create_by!(account: account, user: user, event_key: event_key) { |notice| notice.assign_attributes(attributes) }
  end

  def visible_to?(access)
    return false unless account_id == access.account.id && user_id == access.user.id
    return false if conversation && !access.policy(conversation).show?
    available = JrcNico::ToolCatalog.new(access).available.map { |item| item[:name] }
    authorized_tools = commands.all? do |command|
      ([command.tool] + Array(command.execution_context['source_tools'])).all? { |tool| tool.blank? || available.include?(tool) }
    end
    return false unless authorized_tools
    # Old synthesized replies have no recoverable source manifest; do not expose them after upgrading.
    return false if commands.any? { |command| command.status == 'succeeded' && command.tool.blank? && !command.execution_context.key?('resources') }
    tool = metadata['tool']
    return false if tool && JrcNico::ToolCatalog.new(access).available.none? { |item| item[:name] == tool }
    commands.each do |command|
      ids = Array(command.execution_context['conversation_ids'])
      ids += Array(command.result['conversation_ids']) if command.result.is_a?(Hash)
      ids.uniq.each { |id| access.conversation(id) }
    end

    resources = Array(metadata['resources']) + commands.flat_map { |command| self.class.resources_for(command) }
    resources.all? do |type, id|
      case type
      when 'Contact' then access.contact(id)
      when 'JrcCrm::Lead' then access.crm_scope(JrcCrm::Lead).find(id)
      when 'JrcCrm::Deal' then access.crm_scope(JrcCrm::Deal).find(id)
      when 'JrcCrm::Proposal' then access.crm_scope(JrcCrm::Proposal).find(id)
      when 'JrcCrm::Activity' then access.crm_scope(JrcCrm::Activity, owner: :user_id).find(id)
      when 'AutomationRule'
        rule = access.account.automation_rules.find(id)
        raise Pundit::NotAuthorizedError unless access.account.feature_enabled?('automations') && access.policy(rule).show?

        rule
      when 'JrcCampaigns::Campaign'
        raise Pundit::NotAuthorizedError unless access.campaigns?

        access.account.jrc_campaigns.find(id)
      when 'JrcNico::KnowledgeDocument' then JrcNico::KnowledgeDocument.where(account: access.account).approved.find(id)
      else
        JrcNico::DomainAccess::RESOURCE_TYPES.include?(type) ? JrcNico::DomainAccess.authorize_resource!(access, type, id) : true
      end
    end
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    false
  end

  def snapshot
    { id: id, kind: kind, status: status, body: body, request: request, unread: read_at.nil?,
      conversation_id: conversation&.display_id, contact_name: conversation&.contact&.name,
      command_ids: commands.order(:id).pluck(:id), updated_at: updated_at, metadata: metadata.slice('route_name', 'tool') }
  end

  def self.command_changed!(command)
    return unless %w[awaiting_confirmation browser_pending succeeded failed unknown cancelled].include?(command.status)
    if command.source_notice
      notice = command.source_notice
      notice.update!(status: command.tool.blank? && command.status == 'succeeded' ? 'review' : command.status,
                     body: command.reply.presence || 'Confira a ação do NICO.', read_at: nil)
      if command.status == 'succeeded' && JrcNico::ToolCatalog::TOOLS.dig(command.tool, 2) == true
        JrcNico::NoticePlanJob.perform_later(notice.id)
      end
    elsif %w[succeeded failed unknown].include?(command.status) && command.tool.present?
      result = command.result.is_a?(Hash) ? command.result : {}
      resources = resources_for(command)
      publish!(account: command.session.account, user: command.session.user,
        event_key: "command:#{command.id}:#{command.status}", kind: 'result', status: command.status,
        body: command.reply.presence || 'Confira o resultado da ação.', metadata: { tool: command.tool, resources: resources, route_name: result['route_name'] })
    end
  end

  def self.resources_for(command)
    types = { 'search_contacts' => 'Contact', 'list_leads' => 'JrcCrm::Lead', 'list_deals' => 'JrcCrm::Deal',
              'list_activities' => 'JrcCrm::Activity', 'list_proposals' => 'JrcCrm::Proposal', 'search_knowledge' => 'JrcNico::KnowledgeDocument',
              'list_automations' => 'AutomationRule', 'list_campaigns' => 'JrcCampaigns::Campaign' }
    rows = if command.result.is_a?(Array)
             command.result
           else
             command.result.fetch('items', [command.result])
           end
    resources = rows.filter_map do |row|
      next unless row.is_a?(Hash)
      type = row['resource_type'] || types[command.tool]
      id = row.dig('record', 'id') || row['id']
      [type, id] if type && id
    end
    resources += Array(command.result['resources']) if command.result.is_a?(Hash)
    arguments = command.arguments.to_h
    { 'contact_id' => 'Contact', 'lead_id' => 'JrcCrm::Lead', 'deal_id' => 'JrcCrm::Deal',
      'proposal_id' => 'JrcCrm::Proposal', 'activity_id' => 'JrcCrm::Activity',
      'automation_id' => 'AutomationRule', 'campaign_id' => 'JrcCampaigns::Campaign' }.each do |field, type|
      resources << [type, arguments[field]] if arguments[field]
    end
    (resources + Array(command.execution_context['resources'])).uniq
  end
end
