module JrcRelationship::SignalDispatch
  extend ActiveSupport::Concern
  included do
    after_commit :dispatch_relationship_signal, on: [:create, :update]
  end

  private

  def dispatch_relationship_signal
    return unless account&.feature_enabled?('jrc_relationship')
    JrcRelationship::SignalJob.perform_later(self.class.name, id)
  end
end
