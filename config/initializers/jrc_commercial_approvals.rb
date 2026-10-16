Rails.application.config.to_prepare do
  JrcApprovals::CommercialCatalog.install!
  JrcApprovals::GratuityCatalog.install!
end
