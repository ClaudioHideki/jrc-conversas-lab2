# An additive list scope. The underlying conversation permissions remain authoritative.
class Conversations::SharedInboxScope
  def initialize(conversations:, account:, user:, include_participating: false, member_inboxes_only: false)
    @conversations = conversations
    @account = account
    @user = user
    @include_participating = include_participating
    @member_inboxes_only = member_inboxes_only
  end

  def metadata
    @metadata ||= begin
      ids = member_inbox_ids - Conversations::InboxVisibility.new(account: @account, user: @user).exclusive_inbox_ids
      enabled = allowed? && ids.any?
      shared = enabled ? Conversations::SharedInboxRouting.new(account: @account, user: @user, inbox_ids: ids).perform : []
      # The remote snapshot must not retain access revoked while HTTP was in flight.
      ApplicationRecord.uncached do
        current_metadata(enabled && allowed?, shared)
      end
    end
  end

  def perform
    scope = metadata
    permitted, shared_ids = ApplicationRecord.uncached do
      [Conversations::PermissionFilterService.new(@conversations, @user, @account).perform, allowed? ? scope[:inbox_ids] : []]
    end
    mine = permitted.assigned_to(@user)
    if @include_participating
      participants = ConversationParticipant.where(account_id: @account.id, user_id: @user.id).select(:conversation_id)
      mine = mine.or(permitted.where(id: participants))
    end
    mine.or(permitted.where(inbox_id: shared_ids, assignee_agent_bot_id: nil)).or(historical_scope(permitted))
  end

  # A committed CHAT receipt proves retained history, not live queue authority.
  # Only resolved history in non-exclusive member inboxes participates here.
  def historical_scope(permitted = nil)
    return @conversations.none unless @member_inboxes_only && allowed?

    permitted ||= Conversations::PermissionFilterService.new(@conversations, @user, @account).perform
    receipts = JrcBrokerHistoryReceipt.where(account_id: @account.id, record_kind: 'CHAT')
                                      .joins('INNER JOIN jrc_broker_inbox_bindings b ON b.account_id=jrc_broker_history_receipts.account_id ' \
                                             'AND b.inbox_id=jrc_broker_history_receipts.inbox_id ' \
                                             'AND b.integration_id=jrc_broker_history_receipts.integration_id')
                                      .joins('INNER JOIN jrc_broker_integrations i ON i.account_id=jrc_broker_history_receipts.account_id ' \
                                             'AND i.organization_id=jrc_broker_history_receipts.organization_id')
                                      .select(:conversation_id)
    permitted.where(id: receipts, inbox_id: historical_inbox_ids, status: :resolved, assignee_agent_bot_id: nil)
  end

  def historical_page_ids(page)
    return [] unless @member_inboxes_only

    historical_scope.where(id: page.first(100).map(&:id)).pluck(:display_id)
  end

  private

  def current_metadata(enabled, shared)
    result = { enabled: enabled, inbox_ids: enabled ? (shared & member_inbox_ids).sort : [] }
    result[:member_inbox_ids] = current_member_inbox_ids if @member_inboxes_only
    result[:historical_inbox_ids] = historical_inbox_ids if @member_inboxes_only
    result[:historical_proof_revisions] = historical_proof_revisions if @member_inboxes_only
    supervised = Conversations::InboxVisibility.new(account: @account, user: @user).supervised_inbox_ids
    result[:supervised_inbox_ids] = supervised if supervised.any?
    result
  end

  def current_member_inbox_ids
    @account.account_users.exists?(user_id: @user.id) ? member_inbox_ids.sort : []
  end

  def allowed?
    member = @account.account_users.find_by(user_id: @user.id)
    return false unless member && %w[agent administrator].include?(member.role)
    return true if member.custom_role_id.nil?

    member.permissions.include?('conversation_manage')
  end

  def member_inbox_ids
    InboxMember.where(user_id: @user.id, inbox_id: @account.inboxes.select(:id)).pluck(:inbox_id)
  end

  def historical_inbox_ids
    return [] unless @member_inboxes_only && allowed?

    member_inbox_ids - Conversations::InboxVisibility.new(account: @account, user: @user).exclusive_inbox_ids
  end

  def historical_proof_revisions
    ids = historical_inbox_ids
    return {} if ids.empty?

    integration = JrcBrokerIntegration.find_by(account: @account)
    return {} unless integration

    revisions = JrcBrokerHistoryVisibility.where(account: @account, inbox_id: ids).pluck(:inbox_id, :revision).to_h
    bindings = JrcBrokerInboxBinding.where(account: @account, inbox_id: ids).order(:id)
                                    .pluck(:inbox_id, :id, :integration_id, :instance_id).group_by(&:first)
    ids.to_h do |id|
      fence = [id, revisions.fetch(id, 0), bindings.fetch(id, []), integration.id,
               integration.organization_id, integration.destination_revision, integration.broker_origin]
      [id.to_s, Digest::SHA256.hexdigest(JSON.generate(fence))]
    end
  end
end
