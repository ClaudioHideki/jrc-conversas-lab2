class Whatsapp::RetryReceiptService
  def initialize(inbox, status)
    @inbox = inbox
    @status = status
  end

  def perform
    source_id = @status[:id]
    status = @status[:status]
    return false unless source_id.present? && %w[sent delivered read failed].include?(status)

    # Same lock order as submission finalization: channel, then attempt.
    @inbox.channel.with_lock do
      attempt = WhatsappRetryAttempt.joins(:message).find_by(
        inbox_id: @inbox.id, account_id: @inbox.account_id, messages: { source_id: source_id }
      )
      code = @status[:errors]&.first&.dig(:code).to_s[/\A\d{6}\z/]
      if attempt
        attempt.with_lock { self.class.apply!(attempt, status, code) }
        true
      elsif (original_attempt = WhatsappRetryAttempt.joins(:original_message).find_by(
        inbox_id: @inbox.id, account_id: @inbox.account_id, messages: { source_id: source_id }
      ))
        original = original_attempt.original_message
        original.with_lock do
          unless original.read? || (original.delivered? && status != 'read') || (original.failed? && status == 'sent')
            error = @status[:errors]&.first
            attributes = { status: status }
            attributes[:external_error] = if status == 'failed'
                                            error ? "#{error[:code]}: #{error[:title]}" : original.external_error
                                          end
            original.update!(attributes)
          end
        end
        true
      elsif !@inbox.messages.exists?(source_id: source_id) &&
            WhatsappRetryAttempt.where(inbox_id: @inbox.id, state: %w[submitting unknown]).exists?
        WhatsappRetryReceipt.create_or_find_by!(inbox_id: @inbox.id, source_id: source_id, status: status) do |receipt|
          receipt.error_code = code
        end
        true
      else
        false
      end
    end
  end

  def self.reconcile!(attempt)
    attempt.inbox.channel.with_lock do
      attempt.with_lock do
        source_id = attempt.message.reload.source_id
        next if source_id.blank?

        attempt.transition!('accepted') if %w[submitting unknown].include?(attempt.state)
        WhatsappRetryReceipt.where(inbox_id: attempt.inbox_id, source_id: source_id)
                            .order(Arel.sql("CASE status WHEN 'sent' THEN 0 WHEN 'failed' THEN 1 WHEN 'delivered' THEN 2 ELSE 3 END")).each do |receipt|
          receipt.update!(whatsapp_retry_attempt: attempt)
          apply!(attempt, receipt.status, receipt.error_code)
        end
      end
    end
  end

  def self.apply!(attempt, status, error_code)
    return if attempt.state == 'read'
    return if attempt.state == 'delivered' && status != 'read'
    return if attempt.state == 'failed' && status == 'sent'

    attempt.transition!(status == 'sent' ? 'accepted' : status, error_code: error_code)
  end
end
