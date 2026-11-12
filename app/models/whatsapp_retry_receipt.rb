class WhatsappRetryReceipt < ApplicationRecord
  belongs_to :inbox
  belongs_to :whatsapp_retry_attempt, optional: true
end
