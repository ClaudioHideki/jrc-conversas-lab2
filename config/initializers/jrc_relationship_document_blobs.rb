Rails.application.config.to_prepare do
  [ActiveStorage::Blobs::RedirectController, ActiveStorage::Blobs::ProxyController,
   ActiveStorage::Representations::RedirectController, ActiveStorage::Representations::ProxyController,
   ActiveStorage::DiskController].each do |controller|
    controller.include(JrcRelationship::ProtectedDocumentBlob) unless controller < JrcRelationship::ProtectedDocumentBlob
  end
end
