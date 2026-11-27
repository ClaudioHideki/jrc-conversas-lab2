require 'digest'

class JrcCampaigns::MetaStatusService
  STATUSES = %w[sent delivered read failed].freeze

  def self.record(inbox:, external_id:, status:, timestamp: nil, errors: nil)
    return false unless inbox.channel_type == 'Channel::Whatsapp'
    return false unless STATUSES.include?(status.to_s) && external_id.to_s.present?

    related = JrcCampaigns::Delivery.where(inbox: inbox).where('external_id = ? OR status = ?', external_id, 'sending').exists? ||
              JrcCampaigns::TestDelivery.where(inbox: inbox).where('external_id = ? OR status = ?', external_id, 'sending').exists?
    return false unless related

    # Persist only the provider's error classification, never webhook contacts,
    # tokens, URLs or message contents. Account is obtained from the trusted inbox.
    sanitized = Array(errors).map do |error|
      error.to_h.with_indifferent_access.slice(:code, :title).transform_values { |value| value.to_s.first(300) }
    end
    occurred_at = timestamp.to_s.match?(/\A\d{1,12}\z/) ? Time.at(timestamp.to_i).utc : Time.current
    fingerprint = Digest::SHA256.hexdigest([external_id, status, timestamp, sanitized].to_json)
    event = JrcCampaigns::StatusEvent.create_or_find_by!(inbox: inbox, fingerprint: fingerprint) do |item|
      item.external_id = external_id
      item.status = status
      item.occurred_at = occurred_at
      item.provider_errors = sanitized
    end
    matched = apply(event)
    JrcCampaigns::MetaStatusReplayJob.set(wait: 30.seconds).perform_later(event.id, 0) if !matched && event.previously_new_record?
    matched
  end

  def self.replay(inbox:, external_id:)
    JrcCampaigns::StatusEvent.where(inbox: inbox, external_id: external_id, matched_at: nil).order(:occurred_at, :id).each { |event| apply(event) }
  end

  def self.apply(event)
    event.with_lock do
      return true if event.matched_at

      delivery = JrcCampaigns::Delivery.find_by(inbox_id: event.inbox_id, external_id: event.external_id)
      test = JrcCampaigns::TestDelivery.find_by(inbox_id: event.inbox_id, external_id: event.external_id)
      return false unless delivery || test

      if delivery
        JrcCampaigns::StatusTrackerService.call(external_id: event.external_id, status: event.status, errors: event.provider_errors,
                                                inbox: event.inbox)
      end
      update_test(test, event) if test
      event.update!(matched_at: Time.current)
      true
    end
  end

  def self.update_test(test, event)
    test.with_lock do
      attrs = case event.status
              when 'sent'
                { status: 'sent', sent_at: test.sent_at || event.occurred_at } unless test.delivered_at || test.read_at || test.failed_at
              when 'delivered'
                { status: 'delivered', delivered_at: test.delivered_at || event.occurred_at } unless test.read_at
              when 'read'
                { status: 'read', delivered_at: test.delivered_at || event.occurred_at, read_at: test.read_at || event.occurred_at }
              when 'failed'
                unless test.delivered_at || test.read_at
                  error = event.provider_errors.first.to_h
                  { status: 'failed', failed_at: test.failed_at || event.occurred_at, error_code: error['code'], error_message: error['title'] }
                end
              end
      test.update!(attrs.merge(metadata: test.metadata.merge('provider_status' => event.status))) if attrs
    end
  end
  private_class_method :update_test
end
