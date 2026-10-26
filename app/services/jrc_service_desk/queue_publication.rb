# frozen_string_literal: true

module JrcServiceDesk::QueuePublication
  module_function

  def call(queue, actor)
    definition = JrcServiceDesk::ConfigurationResources.fields('queues', queue)
    version = JrcServiceDesk::QueuePolicyVersion.create!(account: queue.account, unit: queue.unit, queue: queue,
                                                         published_by_membership: actor, version: queue.policy_versions.maximum(:version).to_i + 1,
                                                         definition: definition, digest: JrcServiceDesk::CanonicalJson.digest(definition))
    queue.update!(current_policy_version: version)
    version
  end
end
