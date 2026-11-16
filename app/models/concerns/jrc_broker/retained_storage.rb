module JrcBroker::RetainedStorage
  # ActiveStorage::Attachment#purge calls delete, bypassing destroy callbacks.
  # Blob#delete removes physical bytes; its protection cannot rely on a FK error.
  def purge
    JrcBroker::HistoryRetention.guard(self) { super }
  end

  def purge_later
    JrcBroker::HistoryRetention.guard(self) { super }
  end

  def delete
    JrcBroker::HistoryRetention.guard(self) { super }
  end
end
