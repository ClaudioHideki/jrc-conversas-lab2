Rails.application.config.to_prepare do
  JrcApprovals::CommercialCatalog.install!
  JrcApprovals::GratuityCatalog.install!
  JrcBackoffice::AuthorityCatalog.install!
  JrcRelationship::DistributionApprovalCatalog.install!
end
