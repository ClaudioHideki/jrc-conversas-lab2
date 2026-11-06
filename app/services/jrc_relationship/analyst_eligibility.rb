# Narrow denial for withdrawn CS members, not a new authorization source.
# Serialize new responsibility admission with the final readiness check.
class JrcRelationship::AnalystEligibility
  def self.available?(account_id, user_id)
    AccountUser.exists?(account_id: account_id, user_id: user_id, jrc_relationship_withdrawn_at: nil)
  end

  def self.validate!(record)
    new(record).validate!
  end

  def initialize(record)
    @record = record
  end

  def validate!
    # Shared Service Desk/Backoffice surveys retain their native authorship.
    return if @record.is_a?(JrcRelationship::Survey)

    ids = admitted_owner_ids.compact.uniq
    return if ids.empty?

    JrcRelationship::DistributionApproval.lock_configuration!(@record.account_id)
    blocked = AccountUser.where(account_id: @record.account_id, user_id: ids).where.not(jrc_relationship_withdrawn_at: nil).exists?
    @record.errors.add(:owner, 'is withdrawn from Relationship; choose an eligible current owner') if blocked
  end

  private

  def admitted_owner_ids
    ids = []
    ids << @record.owner_id if @record.new_record? || @record.will_save_change_to_owner_id? || reactivated?
    if @record.is_a?(JrcRelationship::SuccessPlan)
      ids += nested_changes(@record.goals, @record.attribute_in_database('goals'))
      ids += nested_changes(@record.metadata['milestones'], @record.attribute_in_database('metadata').to_h['milestones'])
    elsif @record.is_a?(JrcRelationship::Qbr)
      ids += nested_changes(@record.decisions, @record.attribute_in_database('decisions'))
    end
    ids
  end

  def nested_changes(rows, previous)
    previous = Array(previous)
    check_all = @record.new_record? || reactivated?
    Array(rows).each_with_index.filter_map do |row, index|
      next unless row.is_a?(Hash) && row['owner_id'].present?
      next if !check_all && unchanged_nested_owner?(row, previous[index])

      row['owner_id']
    end
  end

  def unchanged_nested_owner?(row, previous)
    previous.is_a?(Hash) && previous['owner_id'].to_s == row['owner_id'].to_s
  end

  def reactivated?
    return false unless @record.will_save_change_to_status?

    statuses = if @record.is_a?(JrcRelationship::Assignment)
                 JrcRelationship::DistributionCapacityGuard::LOAD_STATUSES
               else
                 JrcRelationship::PortfolioResponsibilities::TYPES.values.find { |model, _| @record.is_a?(model) }&.last || []
               end
    statuses.include?(@record.status) && statuses.exclude?(@record.status_in_database)
  end
end
