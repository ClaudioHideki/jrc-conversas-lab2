class WhatsappRetryAttempt < ApplicationRecord
  belongs_to :account
  belongs_to :inbox
  belongs_to :original_message, class_name: 'Message'
  belongs_to :message
  belongs_to :actor, class_name: 'User', optional: true

  def transition!(state, error_code: nil)
    update!(state: state)
    metadata = { 'attempt_id' => id, 'original_message_id' => original_message_id, 'state' => state }
    attributes = { additional_attributes: message.reload.additional_attributes.merge('whatsapp_retry' => metadata) }
    if %w[accepted delivered read].include?(state)
      attributes.merge!(status: state == 'accepted' ? :sent : state, external_error: nil)
    else
      attributes[:status] = :failed
      attributes[:external_error] = if state == 'failed'
                                      "#{error_code}: #{I18n.t('errors.whatsapp.retry.provider_rejected')}"
                                    elsif %w[unknown cancelled].include?(state)
                                      I18n.t("errors.whatsapp.retry.#{state}")
                                    end
    end
    message.update!(attributes)
  end
end
