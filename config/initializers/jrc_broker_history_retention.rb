Rails.application.config.to_prepare do
  [Account, Inbox, Conversation, Contact, ContactInbox, Message, Attachment,
   JrcBrokerLiveReceipt, JrcBrokerHistoryReceipt, JrcBrokerHistoryMedia,
   ActiveStorage::Blob, ActiveStorage::Attachment].each do |model|
    model.include(JrcBroker::RetainedRecord) unless model < JrcBroker::RetainedRecord
  end

  [ActiveStorage::Blob, ActiveStorage::Attachment].each do |model|
    model.prepend(JrcBroker::RetainedStorage) unless model < JrcBroker::RetainedStorage
  end
end
