require Rails.root.join('app/services/jrc_flows/ownership_hooks')

Rails.application.config.middleware.insert_before 0, JrcFlows::OwnershipHooks::BodyLimit
Rails.application.config.to_prepare do
  {
    JrcFlows::Actions => JrcFlows::OwnershipHooks::Actions,
    JrcFlows::WorkflowEngine => JrcFlows::OwnershipHooks::Workflow,
    JrcFlows::ChatwootClient => JrcFlows::OwnershipHooks::RemoteClient,
    JrcFlows::Delivery => JrcFlows::OwnershipHooks::Delivery,
    JrcRelationship::PlaybookFlowWebhookDelivery => JrcFlows::OwnershipHooks::PlaybookWebhook,
    JrcRelationship::PlaybookFlowResumeJob => JrcFlows::OwnershipEntrypoints::PlaybookResume
  }.each { |target, hook| target.prepend(hook) unless target.ancestors.include?(hook) }
end
