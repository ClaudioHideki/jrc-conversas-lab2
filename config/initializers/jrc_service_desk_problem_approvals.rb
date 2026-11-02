Rails.application.config.to_prepare do
  JrcServiceDesk::ProblemApprovalCatalog.install!
end
