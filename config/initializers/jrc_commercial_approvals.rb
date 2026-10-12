Rails.application.config.to_prepare do
  JrcApprovals::CommercialCatalog.install!
end
