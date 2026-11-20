# frozen_string_literal: true

Rails.application.config.filter_parameters += %i[idempotency_key input_digest]

Rails.application.config.to_prepare do
  [ActiveStorage::Blobs::RedirectController, ActiveStorage::Blobs::ProxyController,
   ActiveStorage::Representations::RedirectController, ActiveStorage::Representations::ProxyController,
   ActiveStorage::DiskController].each do |controller|
    controller.include(JrcContactCenter::ProtectedAudioBlob) unless controller < JrcContactCenter::ProtectedAudioBlob
  end
end
