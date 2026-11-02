Rails.application.config.to_prepare do
  ActiveSupport.on_load(:active_storage_attachment) do
    include JrcBackoffice::ProtectedContractAttachment unless self < JrcBackoffice::ProtectedContractAttachment
  end
  [ActiveStorage::Blobs::RedirectController, ActiveStorage::Blobs::ProxyController,
   ActiveStorage::Representations::RedirectController, ActiveStorage::Representations::ProxyController,
   ActiveStorage::DiskController].each do |controller|
    controller.include(JrcBackoffice::ProtectedContractBlob) unless controller < JrcBackoffice::ProtectedContractBlob
  end
end
