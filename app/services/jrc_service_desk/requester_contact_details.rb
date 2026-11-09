# frozen_string_literal: true

# Contact channels are presentation/delivery data, never evidence of identity.
class JrcServiceDesk::RequesterContactDetails
  def self.call(contact)
    points = JrcCustomers::ContactPoint.where(account_id: contact.account_id, contact_id: contact.id).order(:id)
    { 'name' => contact.name, 'company_id' => contact.company_id,
      'email' => contact.email.presence || points.find { |row| JrcCustomers::Identity::EMAIL_KINDS.include?(row.kind) }&.normalized_value,
      'phone_number' => contact.phone_number.presence || points.find { |row| JrcCustomers::Identity::PHONE_KINDS.include?(row.kind) }&.normalized_value }
  end

  def self.notification_recipient(contact, channel)
    values = call(contact)
    value = values[channel == 'email' ? 'email' : 'phone_number']
    return if value.blank?

    matches = JrcCustomers::IdentityResolver.new(account: contact.account).call(
      email: channel == 'email' ? value : nil, phone: channel == 'email' ? nil : value, country: 'BR'
    )
    value if matches.where.not(id: contact.id).empty?
  end
end
