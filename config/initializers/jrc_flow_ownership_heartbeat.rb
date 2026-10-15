# Startup never waits for an attestation. Acquisition stays closed until the
# observer has measured the live processes and published a valid signature.
Rails.application.config.after_initialize do
  JrcFlows::OwnershipHeartbeat.start!(role: 'rails') unless Sidekiq.server?
end
Sidekiq.configure_server do |config|
  config.on(:startup) { JrcFlows::OwnershipHeartbeat.start!(role: 'worker') }
  config.on(:shutdown) { JrcFlows::OwnershipHeartbeat.stop! }
end
