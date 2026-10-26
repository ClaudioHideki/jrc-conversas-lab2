# The existing authorized SD download endpoints stream files. Protect alternate
# native blob/variant/disk URLs too, without changing unrelated storage behavior.
Rails.application.config.to_prepare do
  [ActiveStorage::Blobs::RedirectController, ActiveStorage::Blobs::ProxyController,
   ActiveStorage::Representations::RedirectController, ActiveStorage::Representations::ProxyController,
   ActiveStorage::DiskController].each do |controller|
    controller.include(RequesterPortal::ProtectedBlob) unless controller < RequesterPortal::ProtectedBlob
  end
end
