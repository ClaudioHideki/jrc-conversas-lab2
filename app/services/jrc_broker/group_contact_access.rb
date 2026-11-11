# Customer contacts remain shared. WhatsApp groups follow conversation/inbox RBAC.
class JrcBroker::GroupContactAccess
  def initialize(account:, user:)
    @account = account
    @user = user
  end

  def restrict(contacts)
    membership = @account.account_users.find_by(user_id: @user.id) if @user.is_a?(User)
    return contacts if membership&.administrator? && membership.custom_role_id.nil?

    normal = excluding_groups(contacts)
    return normal unless membership && @user.is_a?(User)

    visible = Conversations::PermissionFilterService.new(@account.conversations, @user, @account).perform.select(:contact_id)
    normal.or(contacts.where(id: visible))
  end

  def excluding_groups(contacts)
    contacts.where.not(id: group_contacts.select(:id))
  end

  def group?(contact)
    group_contacts.exists?(id: contact.id)
  end

  private

  def group_contacts
    groups = @account.contacts.where("additional_attributes->>'jrc_broker_recipient_kind' = 'GROUP' OR identifier LIKE 'jrc-group-%'")
    # Durable receipts prevent an edited display field from making a private group public.
    recorded = JrcBrokerHistoryReceipt.where(account_id: @account.id, record_kind: 'CHAT').where("recipient->>'kind' = 'GROUP'").select(:contact_id)
    groups.or(@account.contacts.where(id: recorded))
  end
end
