Rails.application.config.to_prepare do
  JrcApprovals::CommercialCatalog.install!
  JrcApprovals::FinancialCatalog.install!
  JrcApprovals::DraftReviewCatalog.install!
  JrcApprovals::GratuityCatalog.install!
  JrcBackoffice::AuthorityCatalog.install!
  JrcRelationship::DistributionApprovalCatalog.install!
end
