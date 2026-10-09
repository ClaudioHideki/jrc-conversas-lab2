class JrcServiceDesk::PublicationPreviewError < StandardError
  def initialize
    super('Publication preview expired or changed; review the current preview')
  end
end
