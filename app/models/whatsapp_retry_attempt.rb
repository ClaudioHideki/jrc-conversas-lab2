class WhatsappRetryAttempt < ApplicationRecord
  belongs_to :account
  belongs_to :inbox
  belongs_to :original_message, class_name: 'Message'
  belongs_to :message
  belongs_to :actor, class_name: 'User', optional: true

  def transition!(state, error_code: nil)
    update!(state: state)
    metadata = { 'attempt_id' => id, 'original_message_id' => original_message_id, 'state' => state,
                 'next_check_at' => next_attempt_at&.iso8601 }
    attributes = { additional_attributes: message.reload.additional_attributes.merge('whatsapp_retry' => metadata) }
    if %w[accepted delivered read].include?(state)
      attributes.merge!(status: state == 'accepted' ? :sent : state, external_error: nil)
    elsif state == 'failed'
      explanation = [error_code.presence, I18n.t('errors.whatsapp.retry.provider_rejected')].compact.join(': ')
      attributes.merge!(status: :failed, external_error: explanation)
    else
      explanation = I18n.t("errors.whatsapp.retry.#{state}") if %w[unknown cancelled].include?(state)
      attributes.merge!(status: :failed, external_error: explanation)
    end
    message.update!(attributes)
  end
end
