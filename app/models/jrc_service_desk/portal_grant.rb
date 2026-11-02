# frozen_string_literal: true

# An explicit access grant to EXISTING native identities. Never provisions a User,
# Contact, ContactInbox, company or operational AccountUser.
class JrcServiceDesk::PortalGrant < JrcServiceDesk::AccountRecord
  belongs_to :user, class_name: '::User'
  belongs_to :granted_by, class_name: '::User'
  belongs_to :company, class_name: 'JrcCustomers::Company'
  belongs_to :contact, class_name: '::Contact'
  belongs_to :inbox, class_name: '::Inbox'
  belongs_to :contact_inbox, class_name: '::ContactInbox'

  validates :role, inclusion: { in: %w[requester manager organization_admin] }
  validates :contact_inbox_id, uniqueness: { scope: %i[user_id account_id company_id] }
  validate :native_references
  validate :additional_contacts

  def self.available_for(user)
    where(user_id: user.id, active: true).where('expires_at IS NULL OR expires_at > ?', Time.current).includes(:account, :company, :contact, :inbox, :contact_inbox)
      .select(&:available?)
  end

  def available?
    active? && (!expires_at || expires_at > Time.current) && account.active? &&
      account.feature_enabled?('jrc_service_desk') && account.internal_attributes['requester_portal_enabled'] == true &&
      company.active? && company.account_id == account_id && contact.account_id == account_id && contact.company_id == company_id &&
      !contact.blocked? && contact_inbox.contact_id == contact_id && contact_inbox.inbox_id == inbox_id &&
      contact_inbox.hmac_verified? && inbox.account_id == account_id && inbox.channel_type == 'Channel::WebWidget'
  end

  def public_context
    { id: id.to_s, organization: company.name, account: account.name, role: role,
      contact: { name: contact.name, email: contact.email, phone_number: contact.phone_number } }
  end

  protected

  def ownership_columns
    super + %i[user_id company_id contact_id inbox_id contact_inbox_id granted_by_id]
  end

  private

  def native_references
    %i[company contact inbox].each { |name| validate_account_reference(name) }
    unless contact && contact.company_id == company_id && contact_inbox && contact_inbox.contact_id == contact_id && contact_inbox.inbox_id == inbox_id
      errors.add(:contact_inbox, 'must bind the existing contact and organization')
    end
    if new_record? && !account&.account_users&.where(user_id: granted_by_id, role: :administrator)&.exists?
      errors.add(:granted_by, 'requires an existing account administrator')
    end
    errors.add(:inbox, 'requires the native customer widget') unless inbox&.channel_type == 'Channel::WebWidget'
  end

  def additional_contacts
    ids = visible_contact_ids
    valid = ids.is_a?(Array) && ids.size <= 100 && ids.uniq == ids && ids.all? { |id| id.is_a?(Integer) && id.positive? }
    valid &&= ids.empty? if role == 'requester'
    valid &&= Contact.where(account_id: account_id, company_id: company_id, blocked: false, id: ids).count == ids.size if valid
    errors.add(:visible_contact_ids, 'requires explicit contacts in the same organization') unless valid
  end
end
