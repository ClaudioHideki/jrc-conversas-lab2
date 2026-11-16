module JrcBroker::RetainedRecord
  extend ActiveSupport::Concern

  included do
    around_destroy :retain_broker_history, prepend: true
  end

  private

  def retain_broker_history(&operation)
    JrcBroker::HistoryRetention.guard(self, &operation)
  end
end
