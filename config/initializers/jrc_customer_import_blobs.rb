Rails.application.config.to_prepare do
  ActiveSupport.on_load(:active_storage_attachment) do
    include JrcCustomers::ProtectedImportAttachment unless self < JrcCustomers::ProtectedImportAttachment
  end
  [ActiveStorage::Blobs::RedirectController, ActiveStorage::Blobs::ProxyController,
   ActiveStorage::Representations::RedirectController, ActiveStorage::Representations::ProxyController,
   ActiveStorage::DiskController].each do |controller|
    controller.include(JrcCustomers::ProtectedImportBlob) unless controller < JrcCustomers::ProtectedImportBlob
  end
end
