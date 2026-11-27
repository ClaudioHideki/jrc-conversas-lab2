class JrcCampaigns::StatusTrackerService
  VALID_STATUSES = %w[sent delivered read failed].freeze

  def self.call(external_id:, status:, errors: nil, inbox: nil)
    scope = inbox ? JrcCampaigns::Delivery.where(inbox: inbox) : JrcCampaigns::Delivery.all
    delivery = scope.find_by(external_id: external_id.to_s)
    return false unless delivery

    normalized_status = status.to_s
    return false unless VALID_STATUSES.include?(normalized_status)

    delivery.with_lock do
      now = Time.current
      attributes = delivery_attributes(delivery, normalized_status, now, errors)
      delivery.update!(attributes) if attributes.present?
      delivery.recipient.with_lock do
        update_recipient(delivery.recipient, delivery, now)
      end
    end
    true
  end

  def self.delivery_attributes(delivery, status, now, errors)
    case status
    when 'sent'
      return {} if delivery.delivered_at.present? || delivery.read_at.present? || delivery.failed_at.present?

      { status: 'sent', sent_at: delivery.sent_at || now }
    when 'delivered'
      return {} if delivery.read_at.present? || delivery.failed_at.present?

      { status: 'delivered', delivered_at: delivery.delivered_at || now }
    when 'read'
      return {} if delivery.failed_at.present?

      {
        status: 'read',
        delivered_at: delivery.delivered_at || now,
        read_at: delivery.read_at || now
      }
    when 'failed'
      return {} if delivery.delivered_at.present? || delivery.read_at.present?

      {
        status: 'failed',
        failed_at: delivery.failed_at || now,
        error_message: extract_error(errors)
      }
    end
  end
  private_class_method :delivery_attributes

  def self.update_recipient(recipient, delivery, now)
    attributes = {}
    attributes[:delivered_at] = recipient.delivered_at || delivery.delivered_at if delivery.delivered_at.present?
    attributes[:read_at] = recipient.read_at || delivery.read_at if delivery.read_at.present?

    if recipient.replied_at.present?
      attributes[:status] = 'replied'
    elsif recipient.read_at.present? || delivery.read_at.present?
      attributes[:status] = 'read'
    elsif recipient.delivered_at.present? || delivery.delivered_at.present?
      attributes[:status] = 'delivered'
    elsif delivery.failed_at.present?
      attributes.merge!(status: 'failed', failed_at: recipient.failed_at || now, error_message: delivery.error_message)
    elsif delivery.sent_at.present?
      attributes[:status] = 'sent'
    end

    recipient.update!(attributes) if attributes.present?
    recipient.execution.refresh_counters!
    recipient.campaign.refresh_counters!
  end
  private_class_method :update_recipient

  def self.extract_error(errors)
    first_error = Array(errors).first
    return first_error.to_s unless first_error.respond_to?(:dig)

    first_error.dig(:title) || first_error.dig('title') || first_error.dig(:message) || first_error.dig('message')
  end
  private_class_method :extract_error
end
