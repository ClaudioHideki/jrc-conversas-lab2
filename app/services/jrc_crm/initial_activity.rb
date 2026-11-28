module JrcCrm
  class InitialActivity
    def self.create!(record, attributes, actor:)
      return if attributes.blank?

      activity = record.activities.new(attributes.merge(account: record.account, user: record.owner || actor))
      result = ActivityDispatchService.new(activity: activity, actor: actor).call
      raise ActiveRecord::RecordInvalid, activity unless result[:success]
    end
  end
end
